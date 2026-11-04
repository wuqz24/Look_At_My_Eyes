// Four-color envelope detector.
//
// The detector intentionally keeps only frame extrema and a sampled fill
// count.  A 16-pixel cell is tested at sixteen positions (4x4), which gives
// enough contour information to separate a filled rectangle from a filled
// circle without storing a frame-sized mask or connected-component queue.

module color_envelope_channel #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer CELL_SHIFT = 4,
    parameter integer MIN_CELLS = 4
)(
    input wire clk,
    input wire rst_n,
    input wire de,
    input wire frame_tick,
    input wire hit,
    input wire [11:0] x,
    input wire [11:0] y,
    output reg valid,
    output reg [11:0] left,
    output reg [11:0] right,
    output reg [11:0] top,
    output reg [11:0] bottom,
    output reg [11:0] cx,
    output reg [11:0] cy,
    output reg [12:0] area,
    output reg [1:0] shape,
    output reg [7:0] confidence
);
    localparam integer CELL_SIZE = (1 << CELL_SHIFT);
    localparam integer GW = (WIDTH + CELL_SIZE - 1) >> CELL_SHIFT;
    localparam integer GH = (HEIGHT + CELL_SIZE - 1) >> CELL_SHIFT;

    // Four evenly spaced sample coordinates in each cell.  For the default
    // 16-pixel cell these are 2, 6, 10 and 14; for the small simulation cell
    // they remain valid at 1, 3, 5 and 7.
    localparam integer SAMPLE0 = CELL_SIZE / 8;
    localparam integer SAMPLE1 = (CELL_SIZE * 3) / 8;
    localparam integer SAMPLE2 = (CELL_SIZE * 5) / 8;
    localparam integer SAMPLE3 = (CELL_SIZE * 7) / 8;

    wire sample_x = de &&
        ((x[CELL_SHIFT-1:0] == SAMPLE0) ||
         (x[CELL_SHIFT-1:0] == SAMPLE1) ||
         (x[CELL_SHIFT-1:0] == SAMPLE2) ||
         (x[CELL_SHIFT-1:0] == SAMPLE3));
    wire sample_y =
        ((y[CELL_SHIFT-1:0] == SAMPLE0) ||
         (y[CELL_SHIFT-1:0] == SAMPLE1) ||
         (y[CELL_SHIFT-1:0] == SAMPLE2) ||
         (y[CELL_SHIFT-1:0] == SAMPLE3));
    wire sample = sample_x && sample_y;
    wire [11:0] cell_x = x >> CELL_SHIFT;
    wire [11:0] cell_y = y >> CELL_SHIFT;

    reg [11:0] min_x, max_x, min_y, max_y;
    reg [15:0] sample_count;

    // Registered frame statistics and a short arithmetic pipeline keep the
    // frame boundary independent from the following shape classification.
    reg stat_valid;
    reg [11:0] min_x_s1, max_x_s1, min_y_s1, max_y_s1;
    reg [15:0] count_s1;
    reg geom_valid;
    reg [15:0] width_s2, height_s2;
    reg [11:0] min_x_s2, max_x_s2, min_y_s2, max_y_s2;
    reg [15:0] count_s2;
    reg metric_valid;
    reg [15:0] box_s3;
    reg [15:0] width_s3, height_s3;
    reg [11:0] min_x_s3, max_x_s3, min_y_s3, max_y_s3;
    reg [15:0] count_s3;
    reg shape_valid;
    reg [1:0] shape_s4;
    reg [15:0] box_s4, count_s4;
    reg [11:0] min_x_s4, max_x_s4, min_y_s4, max_y_s4;

    // A shape change requires two consecutive frame results.  A single
    // missing frame is held, while the second missing frame clears the lock.
    reg stable_valid;
    reg [1:0] stable_shape;
    reg pending_valid;
    reg [1:0] pending_shape;
    reg lost_frame;

    function [11:0] x_start;
        input [11:0] cell_idx;
        begin x_start = cell_idx << CELL_SHIFT; end
    endfunction

    function [11:0] y_start;
        input [11:0] cell_idx;
        begin y_start = cell_idx << CELL_SHIFT; end
    endfunction

    function [11:0] x_edge;
        input [11:0] cell_idx;
        reg [23:0] v;
        begin
            v = (cell_idx + 1'b1) << CELL_SHIFT;
            x_edge = (v > WIDTH) ? WIDTH - 1 : v - 1'b1;
        end
    endfunction

    function [11:0] y_edge;
        input [11:0] cell_idx;
        reg [23:0] v;
        begin
            v = (cell_idx + 1'b1) << CELL_SHIFT;
            y_edge = (v > HEIGHT) ? HEIGHT - 1 : v - 1'b1;
        end
    endfunction

    function [12:0] cell_area;
        input [15:0] box;
        begin cell_area = box >> 4; end
    endfunction

    // Shape encoding: 0 invalid, 1 circle, 2 rectangle, 3 other.
    // Rectangles normally fill at least 14 of the 16 samples in a cell.
    // A circle occupies roughly 60-85 percent of its near-square envelope.
    function [1:0] classify_shape;
        input [15:0] count;
        input [15:0] width;
        input [15:0] height;
        input [15:0] box;
        reg near_square;
        reg [15:0] minimum_count;
        reg [15:0] rectangle_count;
        reg [15:0] circle_count;
        begin
            minimum_count = MIN_CELLS * 8;
            rectangle_count = box - (box >> 3); // 87.5 percent
            circle_count = (box >> 1) + (box >> 4); // 56.25 percent
            near_square = (width * 4 <= height * 5) &&
                          (height * 4 <= width * 5);
            if (count < minimum_count || width < 2 || height < 2 || box == 0)
                classify_shape = 0;
            else if (count >= rectangle_count)
                classify_shape = 2;
            else if (near_square && count >= circle_count)
                classify_shape = 1;
            else
                classify_shape = 3;
        end
    endfunction

    function [7:0] shape_confidence;
        input [1:0] shape_in;
        input [15:0] count;
        input [15:0] box;
        reg [15:0] q94, q78, q55;
        begin
            q94 = box - (box >> 4);
            q78 = box - (box >> 2);
            q55 = (box >> 1) + (box >> 3) + (box >> 6);
            if (shape_in == 0 || box == 0)
                shape_confidence = 0;
            else if (count >= q94)
                shape_confidence = 96;
            else if (count >= q78)
                shape_confidence = 90;
            else if (count >= q55)
                shape_confidence = 82;
            else
                shape_confidence = 70;
        end
    endfunction

    task publish_result;
        input [1:0] shape_in;
        input [15:0] box_in;
        input [15:0] count_in;
        input [11:0] min_x_in;
        input [11:0] max_x_in;
        input [11:0] min_y_in;
        input [11:0] max_y_in;
        begin
            valid <= shape_in != 0;
            shape <= shape_in;
            confidence <= shape_confidence(shape_in, count_in, box_in);
            area <= cell_area(box_in);
            left <= x_start(min_x_in);
            right <= x_edge(max_x_in);
            top <= y_start(min_y_in);
            bottom <= y_edge(max_y_in);
            cx <= (x_start(min_x_in) + x_edge(max_x_in)) >> 1;
            cy <= (y_start(min_y_in) + y_edge(max_y_in)) >> 1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 0;
            left <= 0; right <= 0; top <= 0; bottom <= 0;
            cx <= WIDTH / 2; cy <= HEIGHT / 2;
            area <= 0; shape <= 0; confidence <= 0;

            min_x <= GW; max_x <= 0; min_y <= GH; max_y <= 0;
            sample_count <= 0;
            stat_valid <= 0;
            min_x_s1 <= 0; max_x_s1 <= 0; min_y_s1 <= 0; max_y_s1 <= 0;
            count_s1 <= 0;
            geom_valid <= 0;
            width_s2 <= 0; height_s2 <= 0;
            min_x_s2 <= 0; max_x_s2 <= 0; min_y_s2 <= 0; max_y_s2 <= 0;
            count_s2 <= 0;
            metric_valid <= 0;
            box_s3 <= 0; width_s3 <= 0; height_s3 <= 0;
            min_x_s3 <= 0; max_x_s3 <= 0; min_y_s3 <= 0; max_y_s3 <= 0;
            count_s3 <= 0;
            shape_valid <= 0;
            shape_s4 <= 0; box_s4 <= 0; count_s4 <= 0;
            min_x_s4 <= 0; max_x_s4 <= 0; min_y_s4 <= 0; max_y_s4 <= 0;
            stable_valid <= 0; stable_shape <= 0;
            pending_valid <= 0; pending_shape <= 0; lost_frame <= 0;
        end else begin
            // Consume one completed candidate.  The output is updated only
            // after the same shape has appeared in two frame results.
            if (shape_valid) begin
                if (shape_s4 == 0) begin
                    pending_valid <= 0;
                    if (stable_valid) begin
                        if (lost_frame)
                            begin
                                stable_valid <= 0;
                                stable_shape <= 0;
                                valid <= 0;
                                shape <= 0;
                                area <= 0;
                                confidence <= 0;
                                lost_frame <= 0;
                            end
                        else
                            lost_frame <= 1;
                    end else begin
                        lost_frame <= 0;
                    end
                end else begin
                    lost_frame <= 0;
                    if (stable_valid && shape_s4 == stable_shape) begin
                        publish_result(shape_s4, box_s4, count_s4,
                                       min_x_s4, max_x_s4, min_y_s4, max_y_s4);
                        pending_valid <= 0;
                    end else if (pending_valid && pending_shape == shape_s4) begin
                        stable_valid <= 1;
                        stable_shape <= shape_s4;
                        publish_result(shape_s4, box_s4, count_s4,
                                       min_x_s4, max_x_s4, min_y_s4, max_y_s4);
                        pending_valid <= 0;
                    end else begin
                        pending_valid <= 1;
                        pending_shape <= shape_s4;
                    end
                end
            end

            // Stage 4: classify the registered geometry.
            shape_valid <= metric_valid;
            if (metric_valid) begin
                shape_s4 <= classify_shape(count_s3, width_s3, height_s3, box_s3);
                box_s4 <= box_s3;
                count_s4 <= count_s3;
                min_x_s4 <= min_x_s3; max_x_s4 <= max_x_s3;
                min_y_s4 <= min_y_s3; max_y_s4 <= max_y_s3;
            end

            // Stage 3: calculate the sampled cell-box area.
            metric_valid <= geom_valid;
            if (geom_valid) begin
                box_s3 <= width_s2 * height_s2 * 16;
                width_s3 <= width_s2;
                height_s3 <= height_s2;
                min_x_s3 <= min_x_s2; max_x_s3 <= max_x_s2;
                min_y_s3 <= min_y_s2; max_y_s3 <= max_y_s2;
                count_s3 <= count_s2;
            end

            // Stage 2: calculate the cell-box dimensions.
            geom_valid <= stat_valid;
            if (stat_valid) begin
                width_s2 <= max_x_s1 - min_x_s1 + 1'b1;
                height_s2 <= max_y_s1 - min_y_s1 + 1'b1;
                min_x_s2 <= min_x_s1; max_x_s2 <= max_x_s1;
                min_y_s2 <= min_y_s1; max_y_s2 <= max_y_s1;
                count_s2 <= count_s1;
            end

            // Stage 1: snapshot the finished frame and clear accumulators.
            stat_valid <= frame_tick;
            if (frame_tick) begin
                min_x_s1 <= min_x;
                max_x_s1 <= max_x;
                min_y_s1 <= min_y;
                max_y_s1 <= max_y;
                count_s1 <= sample_count;
                min_x <= GW;
                max_x <= 0;
                min_y <= GH;
                max_y <= 0;
                sample_count <= 0;
            end

            if (sample && hit) begin
                sample_count <= sample_count + 1'b1;
                if (cell_x < min_x) min_x <= cell_x;
                if (cell_x > max_x) max_x <= cell_x;
                if (cell_y < min_y) min_y <= cell_y;
                if (cell_y > max_y) max_y <= cell_y;
            end
        end
    end
endmodule

module color_envelopes #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer CELL_SHIFT = 4,
    parameter integer MIN_CELLS = 4
)(
    input wire clk, rst_n, de, frame_tick,
    input wire [11:0] x, y,
    input wire [23:0] rgb,
    output wire red_valid, green_valid, blue_valid, yellow_valid,
    output wire [11:0] red_left, red_right, red_top, red_bottom, red_cx, red_cy,
    output wire [11:0] green_left, green_right, green_top, green_bottom, green_cx, green_cy,
    output wire [11:0] blue_left, blue_right, blue_top, blue_bottom, blue_cx, blue_cy,
    output wire [11:0] yellow_left, yellow_right, yellow_top, yellow_bottom, yellow_cx, yellow_cy,
    output wire [12:0] red_area, green_area, blue_area, yellow_area,
    output wire [1:0] red_shape, green_shape, blue_shape, yellow_shape,
    output wire [7:0] red_confidence, green_confidence, blue_confidence, yellow_confidence
);
    wire [8:0] rr = {1'b0, rgb[23:16]};
    wire [8:0] gg = {1'b0, rgb[15:8]};
    wire [8:0] bb = {1'b0, rgb[7:0]};

    // The thresholds are deliberately conservative against grey background
    // pixels.  Extended operands avoid 8-bit overflow in the additions.
    wire red_hit = rr > 100 && rr > gg + 40 && rr > bb + 40;
    wire green_hit = gg > 104 && gg > rr + 38 && gg > bb + 32;
    wire blue_hit = bb > 100 && bb > rr + 35 && bb > gg + 25;
    wire yellow_hit = rr > 100 && gg > 100 && rr > bb + 40 && gg > bb + 35 &&
                      rr + 32 >= gg && gg + 32 >= rr;

    color_envelope_channel #(.WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .CELL_SHIFT(CELL_SHIFT), .MIN_CELLS(MIN_CELLS)) red_channel(
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick), .hit(red_hit), .x(x), .y(y),
        .valid(red_valid), .left(red_left), .right(red_right), .top(red_top), .bottom(red_bottom),
        .cx(red_cx), .cy(red_cy), .area(red_area), .shape(red_shape), .confidence(red_confidence));

    color_envelope_channel #(.WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .CELL_SHIFT(CELL_SHIFT), .MIN_CELLS(MIN_CELLS)) green_channel(
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick), .hit(green_hit), .x(x), .y(y),
        .valid(green_valid), .left(green_left), .right(green_right), .top(green_top), .bottom(green_bottom),
        .cx(green_cx), .cy(green_cy), .area(green_area), .shape(green_shape), .confidence(green_confidence));

    color_envelope_channel #(.WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .CELL_SHIFT(CELL_SHIFT), .MIN_CELLS(MIN_CELLS)) blue_channel(
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick), .hit(blue_hit), .x(x), .y(y),
        .valid(blue_valid), .left(blue_left), .right(blue_right), .top(blue_top), .bottom(blue_bottom),
        .cx(blue_cx), .cy(blue_cy), .area(blue_area), .shape(blue_shape), .confidence(blue_confidence));

    color_envelope_channel #(.WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .CELL_SHIFT(CELL_SHIFT), .MIN_CELLS(MIN_CELLS)) yellow_channel(
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick), .hit(yellow_hit), .x(x), .y(y),
        .valid(yellow_valid), .left(yellow_left), .right(yellow_right), .top(yellow_top), .bottom(yellow_bottom),
        .cx(yellow_cx), .cy(yellow_cy), .area(yellow_area), .shape(yellow_shape), .confidence(yellow_confidence));
endmodule
