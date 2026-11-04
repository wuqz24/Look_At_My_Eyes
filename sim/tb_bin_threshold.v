`timescale 1ns/1ps
// Adaptive binary threshold regression.
//
// The first implementation accumulated `R + 2G + B` (0..1020) but kept only
// 8 bits of the frame mean, so the threshold followed a sawtooth
//     threshold = (4 * grey) mod 256
// and the binary view flickered between "all white" and "all black" whenever
// the room brightness moved.  This test feeds uniform grey frames of several
// levels and checks that the published threshold tracks the grey level
// linearly (with the built-in 1.0625 bias and the 240 clamp).
module tb_bin_threshold;
    localparam integer W = 128;
    localparam integer H = 96;
    localparam integer CLK_HZ = 1000000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg de = 1'b0;
    reg vs = 1'b0;
    reg hs = 1'b0;
    reg [23:0] source = 24'h000000;
    reg [23:0] data0 = 24'h000000;
    reg [23:0] data1 = 24'h000000;
    wire rd;
    wire out_de, out_vs, out_hs;
    wire [23:0] out_data;

    hdmi_mixer #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .PIXEL_HZ(CLK_HZ),
                 .SERVO_SELFTEST_HOLD_MS(1)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_video_vsync(vs), .I_video_hsync(hs), .I_video_de(de),
        .I_video_user(1'b0), .I_video_last(1'b0), .I_debug_status(4'd0),
        .I_mode_n(1'b1), .I_color_n(1'b1), .I_arm_n(1'b1),
        .I_capture_toggle(1'b0), .I_sw1(1'b0), .I_sw2(1'b0),
        .O_pan_pwm(), .O_tilt_pwm(), .O_buzzer(),
        .O_time_gray(), .O_video_rd_en(rd), .I_video_rd_data(data1),
        .O_hdmi_vsync(out_vs), .O_hdmi_hsync(out_hs),
        .O_hdmi_de(out_de), .O_hdmi_data(out_data));

    always @(posedge clk) begin
        data0 <= source;
        data1 <= data0;
    end

    task send_grey_frame;
        input [7:0] level;
        integer ix, iy;
        begin
            @(negedge clk); de = 1'b0; vs = 1'b1;
            repeat (3) @(negedge clk);
            vs = 1'b0;
            repeat (8) @(negedge clk);
            for (iy = 0; iy < H; iy = iy + 1) begin
                for (ix = 0; ix < W; ix = ix + 1) begin
                    @(negedge clk);
                    de = 1'b1;
                    source = {level, level, level};
                end
                @(negedge clk); de = 1'b0; source = 24'h000000;
                repeat (3) @(negedge clk);
            end
            repeat (24) @(negedge clk);
        end
    endtask

    task check_level;
        input [7:0] level;
        input integer expect;
        integer k;
        integer got;
        begin
            for (k = 0; k < 14; k = k + 1) send_grey_frame(level);
            got = dut.bin_threshold;
            if (got < expect - 10 || got > expect + 10)
                $fatal(1, "grey %0d: threshold=%0d expected ~%0d (sawtooth?)",
                       level, got, expect);
            $display("  grey %0d -> threshold %0d (expect ~%0d)", level, got, expect);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        // 1.0625 bias, clamped at 240.
        check_level(8'd60,  64);
        check_level(8'd120, 128);
        check_level(8'd180, 191);
        check_level(8'd220, 234);
        check_level(8'd255, 240);
        check_level(8'd80,  85);
        $display("PASS binary threshold: linear in scene brightness, no modulo-256 sawtooth");
        $finish;
    end
endmodule
