// Select the valid red/blue candidate closest to the image centre.
// Green and yellow ports remain for source compatibility but are ignored.
module tracker_target_select #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    // This is the same pixel coordinate used by the on-screen crosshair.
    // Keep it explicit so selection cannot silently fall back to (0,0) or
    // diverge from a video mode's active-area center.
    parameter integer CENTER_X = WIDTH/2,
    parameter integer CENTER_Y = HEIGHT/2
)(
    input wire red_valid, green_valid, blue_valid, yellow_valid,
    input wire [11:0] red_cx, red_cy, green_cx, green_cy,
    input wire [11:0] blue_cx, blue_cy, yellow_cx, yellow_cy,
    output reg valid,
    output reg [11:0] cx, cy,
    output reg [1:0] color
);
    function [12:0] distance;
        input [11:0] px, py;
        reg [12:0] dx, dy;
        begin
            if ({1'b0,px} >= CENTER_X)
                dx = {1'b0,px} - CENTER_X;
            else
                dx = CENTER_X - {1'b0,px};
            if ({1'b0,py} >= CENTER_Y)
                dy = {1'b0,py} - CENTER_Y;
            else
                dy = CENTER_Y - {1'b0,py};
            distance = dx + dy;
        end
    endfunction

    wire [12:0] red_distance = distance(red_cx,red_cy);
    wire [12:0] blue_distance = distance(blue_cx,blue_cy);

    wire choose_blue = blue_valid && (!red_valid || blue_distance < red_distance);

    always @* begin
        valid = red_valid || blue_valid;
        cx = 0;
        cy = 0;
        color = 0;
        if (choose_blue) begin
            cx = blue_cx;
            cy = blue_cy;
            color = 2'd2;
        end else if (red_valid) begin
            cx = red_cx;
            cy = red_cy;
            color = 2'd0;
        end
    end
endmodule
