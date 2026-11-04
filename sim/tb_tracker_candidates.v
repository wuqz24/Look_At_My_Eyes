`timescale 1ns/1ps
// Detector regression, revision B (single measured colour model + corner shape).
//
// Scene colours are the values measured on real board photos:
//   red paper  (222,143,122)  S 0.46   -> must be detected
//   blue paper ( 89,118,151)  S 0.42   -> must be detected
//   skin/hand  (192,166,154)  S 0.20   -> must NOT be detected
//   white board(219,223,215)  S 0.04   -> must NOT be detected
module tb_tracker_candidates;
    localparam integer W = 320;
    localparam integer H = 240;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg de = 1'b0;
    reg frame_tick = 1'b0;
    reg [11:0] x = 0;
    reg [11:0] y = 0;
    reg [23:0] rgb = 24'h303030;

    integer scene = 0;
    integer tgx = 160;
    integer tgy = 120;
    integer tgr = 24;
    integer rect_hw = 40;
    integer rect_hh = 20;

    wire red_valid, green_valid, blue_valid, yellow_valid;
    wire [11:0] red_left, red_right, red_top, red_bottom, red_cx, red_cy;
    wire [11:0] green_left, green_right, green_top, green_bottom, green_cx, green_cy;
    wire [11:0] blue_left, blue_right, blue_top, blue_bottom, blue_cx, blue_cy;
    wire [11:0] yellow_left, yellow_right, yellow_top, yellow_bottom, yellow_cx, yellow_cy;
    wire [15:0] red_area, green_area, blue_area, yellow_area;
    wire [1:0] red_shape, green_shape, blue_shape, yellow_shape;
    wire [7:0] red_conf, green_conf, blue_conf, yellow_conf;
    wire [3:0] red_inst, green_inst, blue_inst, yellow_inst;
    wire [11:0] red_ml, red_mr, red_mt, red_mb;
    wire [11:0] blue_ml, blue_mr, blue_mt, blue_mb;
    wire red_hsv, green_hsv, blue_hsv, yellow_hsv;

    tracker_candidates #(.WIDTH(W), .HEIGHT(H)) dut (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .rgb(rgb),
        .red_valid(red_valid), .green_valid(green_valid),
        .blue_valid(blue_valid), .yellow_valid(yellow_valid),
        .red_left(red_left), .red_right(red_right), .red_top(red_top),
        .red_bottom(red_bottom), .red_cx(red_cx), .red_cy(red_cy),
        .green_left(green_left), .green_right(green_right),
        .green_top(green_top), .green_bottom(green_bottom),
        .green_cx(green_cx), .green_cy(green_cy),
        .blue_left(blue_left), .blue_right(blue_right), .blue_top(blue_top),
        .blue_bottom(blue_bottom), .blue_cx(blue_cx), .blue_cy(blue_cy),
        .yellow_left(yellow_left), .yellow_right(yellow_right),
        .yellow_top(yellow_top), .yellow_bottom(yellow_bottom),
        .yellow_cx(yellow_cx), .yellow_cy(yellow_cy),
        .red_area(red_area), .green_area(green_area),
        .blue_area(blue_area), .yellow_area(yellow_area),
        .red_shape(red_shape), .green_shape(green_shape),
        .blue_shape(blue_shape), .yellow_shape(yellow_shape),
        .red_confidence(red_conf), .green_confidence(green_conf),
        .blue_confidence(blue_conf), .yellow_confidence(yellow_conf),
        .red_instances(red_inst), .green_instances(green_inst),
        .blue_instances(blue_inst), .yellow_instances(yellow_inst),
        .red_mask_left(red_ml), .red_mask_right(red_mr),
        .red_mask_top(red_mt), .red_mask_bottom(red_mb),
        .blue_mask_left(blue_ml), .blue_mask_right(blue_mr),
        .blue_mask_top(blue_mt), .blue_mask_bottom(blue_mb),
        .red_hsv_hit(red_hsv), .green_hsv_hit(green_hsv),
        .blue_hsv_hit(blue_hsv), .yellow_hsv_hit(yellow_hsv));

    localparam [23:0] BG        = 24'h303030;
    localparam [23:0] PAPER_RED = 24'hde8f7a;  // measured red paper
    localparam [23:0] PAPER_RED_DIM = 24'h593931;  // same paper at 40 % light
    localparam [23:0] PAPER_BLU = 24'h597697;  // measured blue paper
    localparam [23:0] SKIN      = 24'hc0a69a;  // measured skin/hand
    localparam [23:0] WHITE     = 24'hdbdfd7;  // white board

    function [23:0] scene_pixel;
        input integer ix;
        input integer iy;
        integer dx, dy, u, v;
        begin
            scene_pixel = (scene == 7) ? WHITE : BG;
            case (scene)
                1: begin      // red disc held next to a hand
                    if ((ix >= (tgx - 70)) && (ix < (tgx - 20)) &&
                        (iy >= (tgy - 30)) && (iy < (tgy + 30)))
                        scene_pixel = SKIN;
                    dx = ix - tgx; dy = iy - tgy;
                    if ((dx * dx + dy * dy) <= (tgr * tgr))
                        scene_pixel = PAPER_RED;
                end
                2: begin      // red rectangle
                    if ((ix >= (tgx - rect_hw)) && (ix < (tgx + rect_hw)) &&
                        (iy >= (tgy - rect_hh)) && (iy < (tgy + rect_hh)))
                        scene_pixel = PAPER_RED;
                end
                3: begin      // blue disc
                    dx = ix - tgx; dy = iy - tgy;
                    if ((dx * dx + dy * dy) <= (tgr * tgr))
                        scene_pixel = PAPER_BLU;
                end
                4: begin      // salt and pepper noise
                    if ((((ix * 7) + (iy * 13)) % 97) == 0)
                        scene_pixel = PAPER_RED;
                end
                5: begin      // skin only
                    if ((ix >= (tgx - 60)) && (ix < (tgx + 60)) &&
                        (iy >= (tgy - 60)) && (iy < (tgy + 60)))
                        scene_pixel = SKIN;
                end
                8: begin      // slightly rotated square (hand-held paper)
                    u = ((ix - tgx) * 990 + (iy - tgy) * 139) / 1000;
                    v = (-(ix - tgx) * 139 + (iy - tgy) * 990) / 1000;
                    if ((u >= -rect_hw) && (u < rect_hw) &&
                        (v >= -rect_hh) && (v < rect_hh))
                        scene_pixel = PAPER_RED;
                end
                6: begin      // small / far disc
                    dx = ix - tgx; dy = iy - tgy;
                    if ((dx * dx + dy * dy) <= (tgr * tgr))
                        scene_pixel = PAPER_RED;
                end
                10: begin     // dim room: warm-lit background + dim paper
                    scene_pixel = 24'h695a4e;
                    dx = ix - tgx; dy = iy - tgy;
                    if ((dx * dx + dy * dy) <= (tgr * tgr))
                        scene_pixel = PAPER_RED_DIM;
                end
                9: begin      // same paper in dim light (40 % brightness)
                    dx = ix - tgx; dy = iy - tgy;
                    if ((dx * dx + dy * dy) <= (tgr * tgr))
                        scene_pixel = PAPER_RED_DIM;
                end
                default: scene_pixel = BG;
            endcase
        end
    endfunction

    task send_frame;
        integer ix, iy;
        begin
            for (iy = 0; iy < H; iy = iy + 1) begin
                for (ix = 0; ix < W; ix = ix + 1) begin
                    @(negedge clk);
                    de = 1'b1;
                    x = ix[11:0];
                    y = iy[11:0];
                    rgb = scene_pixel(ix, iy);
                end
            end
            @(negedge clk);
            de = 1'b0;
            rgb = BG;
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
            repeat (24) @(negedge clk);
        end
    endtask


    task play;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) send_frame;
        end
    endtask

    integer area_big, area_small;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // ---------------------------------------------------------------- 1
        scene = 1; tgx = 200; tgy = 120; tgr = 24;
        play(6);
        if (!red_valid)
            $fatal(1, "scene1: red paper not acquired");
        if (red_shape != 2'd1)
            $fatal(1, "scene1: disc reported as shape=%0d (want circle)", red_shape);
        if (red_cx < 195 || red_cx > 205 || red_cy < 115 || red_cy > 125)
            $fatal(1, "scene1: centre (%0d,%0d) is not the disc centre (200,120)",
                   red_cx, red_cy);
        if (red_area < 1300 || red_area > 2300)
            $fatal(1, "scene1: area=%0d is not the disc area (~1810)", red_area);
        if (red_inst != 4'd1)
            $fatal(1, "scene1: instances=%0d", red_inst);
        if (red_ml < 120 || red_mr > 240 || red_mt < 80 || red_mb > 160)
            $fatal(1, "scene1: mask box (%0d,%0d)-(%0d,%0d) not around the disc",
                   red_ml, red_mt, red_mr, red_mb);
        area_big = red_area;

        // ---------------------------------------------------------------- 2
        scene = 5;
        play(6);
        if (red_valid)
            $fatal(1, "scene5: skin tone object was acquired as red (%0d,%0d)",
                   red_cx, red_cy);

        // ---------------------------------------------------------------- 3
        scene = 2; tgx = 160; tgy = 120; rect_hw = 40; rect_hh = 20;
        play(6);
        if (!red_valid)
            $fatal(1, "scene2: red rectangle not acquired");
        if (red_shape != 2'd2) begin
            $display("DBG rect: valid=%b box=(%0d,%0d)-(%0d,%0d) area=%0d shape=%0d conf=%0d",
                     red_valid, red_left, red_top, red_right, red_bottom, red_area,
                     red_shape, red_conf);
            $display("DBG rect refine: cnt=%0d qcnt=%0d corners tl=%0d tr=%0d bl=%0d br=%0d bbox=%0d bw=%0d bh=%0d",
                     dut.red_refine.cnt, dut.red_refine.q_cnt,
                     dut.red_refine.q_tl, dut.red_refine.q_tr,
                     dut.red_refine.q_bl, dut.red_refine.q_br,
                     dut.red_refine.bbox, dut.red_refine.bw, dut.red_refine.bh);
            $display("DBG rect seps: cx1=%0d cx2=%0d cy1=%0d cy2=%0d corner_shape=%0d pending=%0d pvalid=%b shape=%0d filled=%b empty=%b",
                     dut.red_refine.cx1, dut.red_refine.cx2,
                     dut.red_refine.cy1, dut.red_refine.cy2, dut.red_refine.corner_shape, dut.red_refine.shape_pending, dut.red_refine.shape_pending_valid, dut.red_refine.shape, dut.red_refine.corners_high, dut.red_refine.corners_low);
            $fatal(1, "scene2: rectangle reported as shape=%0d", red_shape);
        end
        if (red_cx < 156 || red_cx > 164 || red_cy < 116 || red_cy > 124)
            $fatal(1, "scene2: rectangle centre (%0d,%0d)", red_cx, red_cy);
        if (red_area < 2800 || red_area > 3600)
            $fatal(1, "scene2: rectangle area=%0d (want ~3200)", red_area);

        // ---------------------------------------------------------------- 3a
        // Hand-held paper is never perfectly axis aligned: a 5 degree rotated
        // square must still be RECTANGLE (it used to fall through to OTHER).
        scene = 8; tgx = 160; tgy = 120; rect_hw = 60; rect_hh = 40;
        play(8);
        if (!red_valid || red_shape != 2'd2)
            $fatal(1, "scene8: 8-degree rotated 1.5:1 rectangle reported as shape=%0d", red_shape);
        if (red_cx < 155 || red_cx > 165 || red_cy < 115 || red_cy > 125)
            $fatal(1, "scene8: rotated rectangle centre (%0d,%0d)", red_cx, red_cy);

        // ---------------------------------------------------------------- 4
        scene = 6; tgx = 90; tgy = 70; tgr = 9;
        play(9);
        if (!red_valid)
            $fatal(1, "scene6: small red disc not acquired");
        if (red_cx < 85 || red_cx > 95 || red_cy < 65 || red_cy > 75)
            $fatal(1, "scene6: small disc centre (%0d,%0d)", red_cx, red_cy);
        if (red_shape != 2'd1)
            $fatal(1, "scene6: small disc reported as shape=%0d", red_shape);
        area_small = red_area;

        // Area must scale with size: the same colour at r=24 covers far more
        // pixels than at r=9 (the old 13-bit path saturated and froze).
        if (area_small >= area_big)
            $fatal(1, "area did not scale with target size: small=%0d big=%0d",
                   area_small, area_big);

        // ---------------------------------------------------------------- 5
        scene = 3; tgx = 160; tgy = 120; tgr = 24;
        play(6);
        if (!blue_valid)
            $fatal(1, "scene3: blue disc not acquired");
        if (blue_cx < 152 || blue_cx > 168 || blue_cy < 112 || blue_cy > 128)
            $fatal(1, "scene3: blue centre (%0d,%0d)", blue_cx, blue_cy);
        if (blue_shape != 2'd1)
            $fatal(1, "scene3: blue disc reported as shape=%0d", blue_shape);
        if (blue_area < 1300 || blue_area > 2300)
            $fatal(1, "scene3: blue area=%0d", blue_area);
        if (blue_ml > 132 || blue_mr < 188 || blue_mt > 93 || blue_mb < 147)
            $fatal(1, "scene3: blue mask box (%0d,%0d)-(%0d,%0d)",
                   blue_ml, blue_mt, blue_mr, blue_mb);

        // ---------------------------------------------------------------- 5b
        // Same paper at 40 % brightness: detection and mask must survive a
        // dimmer room (the absolute V/chroma floors used to kill it here).
        scene = 9; tgx = 160; tgy = 120; tgr = 24;
        play(6);
        if (!red_valid)
            $fatal(1, "scene9: dim red paper not acquired");
        if (red_shape != 2'd1)
            $fatal(1, "scene9: dim disc reported as shape=%0d", red_shape);
        if (red_cx < 155 || red_cx > 165 || red_cy < 115 || red_cy > 125)
            $fatal(1, "scene9: dim disc centre (%0d,%0d)", red_cx, red_cy);
        if (red_area < 1300)
            $fatal(1, "scene9: dim disc area=%0d", red_area);

        // ---------------------------------------------------------------- 5c
        // Dim room: warm-lit background (which used to flood HITS with red) plus
        // the dim paper.  The paper must still be the selected target.
        scene = 10; tgx = 160; tgy = 120; tgr = 24;
        play(6);
        if (!red_valid)
            $fatal(1, "scene10: dim room target lost");
        if (red_cx < 155 || red_cx > 165 || red_cy < 115 || red_cy > 125)
            $fatal(1, "scene10: centre (%0d,%0d) is not the dim paper", red_cx, red_cy);
        if (red_area < 1300)
            $fatal(1, "scene10: area=%0d not the paper", red_area);

        // ---------------------------------------------------------------- 6
        scene = 4;
        play(6);
        if (red_valid || blue_valid)
            $fatal(1, "scene4: speckle noise produced a candidate");

        // ---------------------------------------------------------------- 7
        scene = 7;
        play(6);
        if (red_valid || blue_valid)
            $fatal(1, "scene7: white board produced a candidate");

        $display("PASS tracker_candidates: measured colours, object centre, target-only mask, corner shape, scaled area");
        $finish;
    end
endmodule
