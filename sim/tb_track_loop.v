`timescale 1ns/1ps
// Closed-loop tracker regression.
//
// A red paper disc is held next to a large skin-toned object (the hand) and
// the scene is generated from the gimbal's own pulse command, so the test
// exercises the real loop: detector -> published centre -> servo -> picture
// motion.  It checks the four reported field problems at system level:
//   * the loop settles with the object centre on the crosshair instead of
//     stopping tens of pixels short;
//   * POSX/POSY (status_cx/status_cy) equal the object centre, not the centre
//     of a box merged with the hand;
//   * the on-screen mask covers the disc only and never the skin-tone object;
//   * the mask and status do not tear at the frame boundary.
module tb_track_loop;
    localparam integer W = 128;
    localparam integer H = 96;
    localparam integer CLK_HZ = 1000000;
    localparam integer CX = W/2;
    localparam integer CY = H/2;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg de = 1'b0;
    reg vs = 1'b0;
    reg hs = 1'b0;
    reg [23:0] source = 24'h303030;
    reg [23:0] data0 = 24'h303030;
    reg [23:0] data1 = 24'h303030;

    // Where the object sits relative to the gimbal axis, in pixels.
    integer obj_offset = 20;
    integer obj_offset_y = 15;
    integer tx = CX + 20;
    integer ty = CY + 15;
    integer tr = 12;
    integer plant_num = 1;   // px per quarter-microsecond
    integer plant_den = 2;
    integer pan_at_frame_start = 6000;

    integer out_x = 0;
    integer out_y = 0;
    integer frame_pixels = 0;
    integer mask_count = 0;
    integer mask_min_x = W;
    integer mask_max_x = -1;
    integer mask_min_y = H;
    integer mask_max_y = -1;
    reg checking = 1'b0;
    reg output_vs_prev = 1'b0;

    wire rd;
    wire out_de, out_vs, out_hs;
    wire [23:0] out_data;
    wire pan_pwm, tilt_pwm;

    hdmi_mixer #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .PIXEL_HZ(CLK_HZ),
                 .SERVO_SELFTEST_HOLD_MS(1)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_video_vsync(vs), .I_video_hsync(hs), .I_video_de(de),
        .I_video_user(1'b0), .I_video_last(1'b0), .I_debug_status(4'd0),
        .I_mode_n(1'b1), .I_color_n(1'b1), .I_arm_n(1'b1),
        .I_capture_toggle(1'b0), .I_sw1(1'b0), .I_sw2(1'b0),
        .O_pan_pwm(pan_pwm), .O_tilt_pwm(tilt_pwm), .O_buzzer(),
        .O_time_gray(), .O_video_rd_en(rd), .I_video_rd_data(data1),
        .O_hdmi_vsync(out_vs), .O_hdmi_hsync(out_hs),
        .O_hdmi_de(out_de), .O_hdmi_data(out_data));

    always @(posedge clk) begin
        data0 <= source;
        data1 <= data0;
        #1;
        if (out_vs && !output_vs_prev) begin
            out_x = 0;
            out_y = 0;
        end
        output_vs_prev = out_vs;
        if (out_de) begin
            if (checking && (out_data == 24'hff3030)) begin
                mask_count = mask_count + 1;
                if (out_x < mask_min_x) mask_min_x = out_x;
                if (out_x > mask_max_x) mask_max_x = out_x;
                if (out_y < mask_min_y) mask_min_y = out_y;
                if (out_y > mask_max_y) mask_max_y = out_y;
            end
            if (out_x == W-1) begin
                out_x = 0;
                out_y = out_y + 1;
            end else begin
                out_x = out_x + 1;
            end
        end
    end

    function [23:0] scene_pixel;
        input integer px;
        input integer py;
        integer ddx, ddy;
        begin
            scene_pixel = 24'h303030;
            // Skin tone hand: passes the loose colour test, fails the strict one.
            if ((px >= (tx - 36)) && (px < (tx - 13)) &&
                (py >= (ty - 18)) && (py < (ty + 18)))
                scene_pixel = 24'hc0a69a;
            ddx = px - tx;
            ddy = py - ty;
            if ((ddx * ddx + ddy * ddy) <= (tr * tr))
                scene_pixel = 24'hde8f7a;
        end
    endfunction

    task send_frame;
        integer ix, iy;
        begin
            // Simple gimbal plant: the object moves on screen with the pulse
            // command.  pan_q is read from the DUT, so the loop closes through
            // the real controller.
            pan_at_frame_start = dut.servos.pan_q;
            tx = CX + obj_offset + ((pan_at_frame_start - 6000) * plant_num) / plant_den;
            // TILT_SIGN is +1 in the mixer, so the plant coupling is negative:
            // a longer tilt pulse moves the object up in the picture.
            ty = CY + obj_offset_y -
                 (((dut.servos.tilt_q - 6000) * plant_num) / plant_den);
            @(negedge clk);
            de = 1'b0; vs = 1'b1;
            repeat (3) @(negedge clk);
            vs = 1'b0;
            repeat (10) @(negedge clk);
            for (iy = 0; iy < H; iy = iy + 1) begin
                for (ix = 0; ix < W; ix = ix + 1) begin
                    @(negedge clk);
                    de = 1'b1;
                    source = scene_pixel(ix, iy);
                end
                @(negedge clk); de = 1'b0; source = 24'h303030;
                repeat (4) @(negedge clk);
            end
            // Vertical blanking must be long enough for stage A/B to finish
            // (stage A publishes its ROI about 10 clocks after frame_tick).
            repeat (30) @(negedge clk);
            $display("TRK pan_q=%0d tx=%0d cx=%0d shape=%0d valid=%b latch=%b moving=%b fx=%0d",
                     dut.servos.pan_q, tx, dut.status_cx, dut.tgt_shape,
                     dut.tgt_valid, dut.track_latched, dut.moving, dut.servos.fx);
        end
    endtask

    integer i;
    integer settled_pan;
    integer diff;

    initial begin
        repeat (6) @(negedge clk);
        rst_n = 1'b1;

        // Let the servo self-test finish and acquire the target.
        for (i = 0; i < 56; i = i + 1) send_frame;

        $display("INFO settled: pan_q=%0d pan_us=%0d tx=%0d error=%0d status_cx=%0d",
                 dut.servos.pan_q, dut.servos.pan_us, tx, tx - CX, dut.status_cx);
        $display("INFO settled: tilt_q=%0d tilt_us=%0d ty=%0d error=%0d status_cy=%0d",
                 dut.servos.tilt_q, dut.servos.tilt_us, ty, ty - CY, dut.status_cy);

        if (dut.servos.pan_q == 6000)
            $fatal(1, "servo never moved: the loop is not closing");
        if (!dut.track_latched)
            $fatal(1, "target was not locked");
        if (!dut.startup_done || dut.servos.fault_safe)
            $fatal(1, "servo did not reach tracking (startup=%b safe=%b)",
                   dut.startup_done, dut.servos.fault_safe);
        diff = tx - CX;
        if (diff < 0) diff = -diff;
        if (diff > 6)
            $fatal(1, "loop settled with the object %0d px off centre (pan_q=%0d)",
                   diff, dut.servos.pan_q);
        diff = ty - CY;
        if (diff < 0) diff = -diff;
        if (diff > 6)
            $fatal(1, "loop settled with the object %0d px off centre vertically (tilt_q=%0d)",
                   diff, dut.servos.tilt_q);

        // The published centre must be the disc centre, not the merged box.
        if (dut.status_cx < (tx - 2) || dut.status_cx > (tx + 2))
            $fatal(1, "POSX=%0d is not the disc centre %0d", dut.status_cx, tx);
        if (dut.status_cy < (ty - 2) || dut.status_cy > (ty + 2))
            $fatal(1, "POSY=%0d is not the disc centre %0d", dut.status_cy, ty);

        // Mask must be present, must cover the disc, must not reach the hand.
        checking = 1'b1;
        repeat (3) send_frame;
        checking = 1'b0;
        $display("INFO mask: count=%0d box=(%0d,%0d)-(%0d,%0d) disc=(%0d,%0d) r=%0d",
                 mask_count, mask_min_x, mask_min_y, mask_max_x, mask_max_y, tx, ty, tr);
        if (mask_count < 300)
            $fatal(1, "mask missing on the object: %0d pixels", mask_count);
        if (mask_min_x < (tx - 18) || mask_max_x > (tx + 18) ||
            mask_min_y < (ty - 18) || mask_max_y > (ty + 18))
            $fatal(1, "mask escaped the object: box=(%0d,%0d)-(%0d,%0d) disc=(%0d,%0d)",
                   mask_min_x, mask_min_y, mask_max_x, mask_max_y, tx, ty);
        if (mask_min_x < (tx - 14))
            $fatal(1, "mask painted the skin tone hand: min_x=%0d disc_left=%0d",
                   mask_min_x, tx - tr);

        // Steady state: the command must not keep walking after settling.
        settled_pan = dut.servos.pan_q;
        repeat (6) send_frame;
        if (dut.servos.pan_q != settled_pan)
            $fatal(1, "loop still moving after settling: %0d -> %0d",
                   settled_pan, dut.servos.pan_q);
        if (dut.servo_limit)
            $fatal(1, "software pulse limit reached inside the normal range");

        // Move the object and confirm the loop follows it back to the centre.
        // Changing the plant offset is equivalent to nudging the gimbal.
        plant_den = 1;   // twice the coupling: the same error now moves faster
        repeat (24) send_frame;
        diff = tx - CX;
        if (diff < 0) diff = -diff;
        if (diff > 6)
            $fatal(1, "loop did not recover after the plant gain changed: %0d px", diff);

        $display("PASS track loop: centred object, POSX/POSY = object centre, target-only mask, stable servo");
        $finish;
    end
endmodule
