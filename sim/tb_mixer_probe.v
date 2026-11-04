`timescale 1ns/1ps
module tb_mixer_probe;
    localparam integer W = 320;
    localparam integer H = 240;
    localparam integer CLK_HZ = 1000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg de = 1'b0;
    reg vs = 1'b0;
    reg hs = 1'b0;
    reg [23:0] source = 24'h202020;
    reg [23:0] data0 = 24'h202020;
    reg [23:0] data1 = 24'h202020;
    wire rd;
    wire out_de, out_vs, out_hs;
    wire [23:0] out_data;
    integer frame_no;
    integer mask_count;
    integer output_x, output_y;
    integer output_pixels;
    reg output_check;

    hdmi_mixer #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .PIXEL_HZ(CLK_HZ),
                 .COLOR_REFERENCE(0)) dut(
        .I_clk(clk), .I_rst_n(rst_n),
        .I_video_vsync(vs), .I_video_hsync(hs), .I_video_de(de),
        .I_video_user(1'b0), .I_video_last(1'b0), .I_debug_status(4'd0),
        .I_mode_n(1'b1), .I_color_n(1'b1), .I_arm_n(1'b1),
        .I_capture_toggle(1'b0), .I_sw1(1'b0), .I_sw2(1'b0),
        .O_pan_pwm(), .O_tilt_pwm(), .O_buzzer(), .O_time_gray(),
        .O_video_rd_en(rd), .I_video_rd_data(data1),
        .O_hdmi_vsync(out_vs), .O_hdmi_hsync(out_hs),
        .O_hdmi_de(out_de), .O_hdmi_data(out_data));

    always @(posedge clk) begin
        data0 <= source;
        data1 <= data0;
        #1;
        if (output_check && out_de) begin
            if (output_x < 160 && output_y < 160) begin
                // The production logo intentionally occupies the upper-left
                // 160x160 pixels; its sparse pixels are not camera data.
            end else if ((output_x == W/2 && output_y >= H/2-12 && output_y <= H/2+12) ||
                         (output_y == H/2 && output_x >= W/2-12 && output_x <= W/2+12)) begin
                if (out_data !== 24'hffffff)
                    $fatal(1, "center cross is not at image center x=%0d y=%0d data=%h", output_x, output_y, out_data);
            end else if (out_data !== 24'h202020) begin
                $fatal(1, "pixel/coordinate pipeline mismatch x=%0d y=%0d data=%h", output_x, output_y, out_data);
            end
            output_pixels = output_pixels + 1;
            if (output_x == W-1) begin
                output_x = 0;
                output_y = output_y + 1;
            end else begin
                output_x = output_x + 1;
            end
        end
        if (out_de && (out_data == 24'hff3030 || out_data == 24'h40b0ff ||
                       out_data == 24'h40ff40 || out_data == 24'hffff30))
            mask_count = mask_count + 1;
    end

    task pulse_frame_start;
        begin
            @(negedge clk); vs = 1'b1;
            repeat (3) @(negedge clk);
            vs = 1'b0;
            repeat (5) @(negedge clk);
        end
    endtask

    task send_frame;
        input integer scenario;
        integer xx, yy;
        begin
            pulse_frame_start;
            output_check = (scenario == 99);
            output_x = 0;
            output_y = 0;
            if (scenario == 99)
                output_pixels = 0;
            for (yy = 0; yy < H; yy = yy + 1) begin
                for (xx = 0; xx < W; xx = xx + 1) begin
                    @(negedge clk);
                    de = 1'b1;
                    source = 24'h202020;
                    if (scenario == 99)
                        source = 24'h202020;
                    if (scenario == 0 && xx >= 14 && xx < 20 && yy >= 9 && yy < 15)
                        source = 24'hff0000;
                    if (scenario == 1 && xx >= 3 && xx < 9 && yy >= 3 && yy < 9)
                        source = 24'hff0000;
                    if (scenario == 2 && xx >= 3 && xx < 9 && yy >= 3 && yy < 9)
                        source = 24'h0000ff;
                    if (scenario == 2 && xx >= 22 && xx < 28 && yy >= 14 && yy < 20)
                        source = 24'h00ff00;
                end
                @(negedge clk); de = 1'b0; source = 24'h202020;
                repeat (2) @(negedge clk);
            end
            repeat (8) @(negedge clk);
            frame_no = frame_no + 1;
            $display("PROBE frame=%0d scenario=%0d alive=%b tick=%b age=%0d red_hit=%b blue_hit=%b red_valid=%b red_shape=%0d red_cx=%0d red_cy=%0d blue_valid=%b mask_count=%0d state=%0d", frame_no, scenario,
                     dut.source_alive, dut.frame_tick, dut.stream_age,
                     dut.red_loose_hit, dut.blue_loose_hit, dut.red_valid, dut.red_shape,
                     dut.red_cx, dut.red_cy, dut.blue_valid, mask_count,
                     dut.servos.state);
        end
    endtask

    initial begin
        frame_no = 0;
        mask_count = 0;
        output_check = 1'b0;
        output_x = 0;
        output_y = 0;
        output_pixels = 0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        send_frame(99);
        send_frame(0);
        send_frame(1);
        send_frame(2);
        repeat (20) @(negedge clk);
        if (output_pixels == 0)
            $fatal(1, "mixer produced no checked active pixels");
        $display("PASS mixer probe");
        $finish;
    end
endmodule
