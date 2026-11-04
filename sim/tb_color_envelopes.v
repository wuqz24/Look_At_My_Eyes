`timescale 1ns/1ps

module tb_color_envelopes;
    localparam integer W = 64;
    localparam integer H = 32;
    reg clk = 0;
    reg rst_n = 0;
    reg de = 0;
    reg frame_tick = 0;
    reg [11:0] x = 0;
    reg [11:0] y = 0;
    reg [23:0] rgb = 0;

    wire red_valid, green_valid, blue_valid, yellow_valid;
    wire [11:0] red_left, red_right, red_top, red_bottom, red_cx, red_cy;
    wire [11:0] green_left, green_right, green_top, green_bottom, green_cx, green_cy;
    wire [11:0] blue_left, blue_right, blue_top, blue_bottom, blue_cx, blue_cy;
    wire [11:0] yellow_left, yellow_right, yellow_top, yellow_bottom, yellow_cx, yellow_cy;
    wire [12:0] red_area, green_area, blue_area, yellow_area;
    wire [1:0] red_shape, green_shape, blue_shape, yellow_shape;
    wire [7:0] red_confidence, green_confidence, blue_confidence, yellow_confidence;

    color_envelopes #(.WIDTH(W), .HEIGHT(H), .CELL_SHIFT(3), .MIN_CELLS(2)) dut (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .rgb(rgb),
        .red_valid(red_valid), .green_valid(green_valid), .blue_valid(blue_valid), .yellow_valid(yellow_valid),
        .red_left(red_left), .red_right(red_right), .red_top(red_top), .red_bottom(red_bottom),
        .red_cx(red_cx), .red_cy(red_cy), .green_left(green_left), .green_right(green_right),
        .green_top(green_top), .green_bottom(green_bottom), .green_cx(green_cx), .green_cy(green_cy),
        .blue_left(blue_left), .blue_right(blue_right), .blue_top(blue_top), .blue_bottom(blue_bottom),
        .blue_cx(blue_cx), .blue_cy(blue_cy), .yellow_left(yellow_left), .yellow_right(yellow_right),
        .yellow_top(yellow_top), .yellow_bottom(yellow_bottom), .yellow_cx(yellow_cx), .yellow_cy(yellow_cy),
        .red_area(red_area), .green_area(green_area), .blue_area(blue_area), .yellow_area(yellow_area),
        .red_shape(red_shape), .green_shape(green_shape), .blue_shape(blue_shape), .yellow_shape(yellow_shape),
        .red_confidence(red_confidence), .green_confidence(green_confidence),
        .blue_confidence(blue_confidence), .yellow_confidence(yellow_confidence));

    always #5 clk = ~clk;

    task pixel;
        input integer px;
        input integer py;
        input [23:0] p;
        begin
            @(negedge clk);
            x = px; y = py; rgb = p; de = 1'b1;
        end
    endtask

    task sample_frame;
        input integer kind;
        integer ix, iy, dx, dy;
        reg [23:0] p;
        reg target;
        begin
            for (iy = 0; iy < H; iy = iy + 1) begin
                for (ix = 0; ix < W; ix = ix + 1) begin
                    p = 24'h202020;
                    target = 1'b0;
                    // Every target is 16x16 pixels and is aligned to the
                    // 8-pixel sample grid used by the small test instance.
                    if (ix >= 16 && ix < 32 && iy >= 8 && iy < 24) begin
                        dx = ix - 24;
                        dy = iy - 16;
                        case (kind)
                            0: target = 1'b1; // red rectangle
                            1: target = ((dx*dx + dy*dy) <= 64); // red circle
                            2: target = 1'b1; // yellow rectangle
                            3: target = ((dx*dx + dy*dy) <= 64); // yellow circle
                            4: target = 1'b1; // blue rectangle
                            5: target = ((dx*dx + dy*dy) <= 64); // blue circle
                            6: target = 1'b1; // green rectangle
                            7: target = ((dx*dx + dy*dy) <= 64); // green circle
                            default: target = 1'b0;
                        endcase
                    end
                    if (target) begin
                        case (kind)
                            0,1: p = 24'he02020;
                            2,3: p = 24'he0e020;
                            4,5: p = 24'h2020e0;
                            6,7: p = 24'h20e020;
                            default: p = 24'h202020;
                        endcase
                    end
                    pixel(ix, iy, p);
                end
            end
            @(negedge clk); de = 1'b0;
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (7) @(posedge clk);
        end
    endtask

    task expect_shape;
        input [1:0] expected;
        input [1:0] actual;
        input [8*24-1:0] name;
        begin
            if (actual !== expected)
                $fatal(1, "%0s shape expected=%0d got=%0d", name, expected, actual);
        end
    endtask

    task expect_detection;
        input integer kind;
        reg [1:0] wanted_shape;
        begin
            sample_frame(kind);
            sample_frame(kind);
            case (kind)
                0,2,4,6: wanted_shape = 2'd2;
                default: wanted_shape = 2'd1;
            endcase
            case (kind)
                0,1: begin if (!red_valid) $fatal(1,"red invalid kind=%0d",kind); expect_shape(wanted_shape,red_shape,"red"); end
                2,3: begin if (!yellow_valid) $fatal(1,"yellow invalid kind=%0d",kind); expect_shape(wanted_shape,yellow_shape,"yellow"); end
                4,5: begin if (!blue_valid) $fatal(1,"blue invalid kind=%0d",kind); expect_shape(wanted_shape,blue_shape,"blue"); end
                6,7: begin if (!green_valid) $fatal(1,"green invalid kind=%0d",kind); expect_shape(wanted_shape,green_shape,"green"); end
            endcase
        end
    endtask

    task blank_frame;
        integer ix, iy;
        begin
            for (iy = 0; iy < H; iy = iy + 1)
                for (ix = 0; ix < W; ix = ix + 1)
                    pixel(ix, iy, 24'h202020);
            @(negedge clk); de = 1'b0;
            @(negedge clk); frame_tick = 1'b1;
            @(negedge clk); frame_tick = 1'b0;
            repeat (7) @(posedge clk);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        expect_detection(0);
        expect_detection(1);
        expect_detection(2);
        expect_detection(3);
        expect_detection(4);
        expect_detection(5);
        expect_detection(6);
        expect_detection(7);

        // One missing frame is held; the second consecutive missing frame clears.
        blank_frame();
        if (!green_valid) $fatal(1, "single missing frame was not held");
        blank_frame();
        if (green_valid || green_shape != 0) $fatal(1, "two missing frames were not cleared");
        $display("PASS color_envelopes: red/yellow/blue/green rectangle+circle classification and dropout lock");
        $finish;
    end
endmodule
