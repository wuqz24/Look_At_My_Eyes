// ============================================================================
//  tracker_candidates.v   2026-11-03 (revision B)
//
//  Red / blue target detector for the HX1P35 gimbal tracker.
//
//  Why revision B exists
//  ---------------------
//  Revision A introduced a "strict" colour model (S >= 62.5 %) on top of a
//  loose one, and used it both for acquisition and for the visible mask.
//  Measured on the real camera output (board photos) the painted paper is:
//
//      red   paper : R 222, G 143, B 122   hue 16 deg, S 0.42 .. 0.49, V 210+
//      blue  paper : R  89, G 118, B 151   hue 210 deg, S 0.31 .. 0.47, V 137+
//      skin / hand : R 192, G 166, B 154   hue 18 deg, S 0.14 .. 0.25, V 190
//      white board :                      S 0.02 .. 0.07
//
//  So the camera renders the paper at only ~45 % saturation: the strict model
//  almost never fired, the visible mask degraded to a few isolated pixels on
//  the brightest brush strokes, the shape was computed from that speckle (so
//  it flipped between RECTANGLE and OTHER) and the published area was the
//  speckle count instead of the object.  That is exactly what was reported.
//
//  Revision B therefore uses ONE colour model whose threshold sits in the gap
//  between paper (>= 0.31) and skin (<= 0.25):
//
//      S = chroma/value >= 9/32 (28 %), |hue| <= 45 deg, V >= 96,
//      chroma >= 20 (absolute), dominant channel must be R (red) or B (blue)
//
//  Structure (unchanged, two raster stages, no frame buffer):
//
//   stage A  tracker_region_channel   streaming run/region table, one ROI per
//   stage B  tracker_roi_refine       measure that ROI only, publish the
//                                     compact box, centre, area and shape
//
//  Shape is now decided by a *corner occupancy* test, which is insensitive to
//  brush texture and to a few missing pixels: for an axis-aligned rectangle
//  the four quarter-size corner cells of the box are full, for a circle they
//  are almost empty (~5 %).  A two-frame confirm keeps the label from
//  flickering.
//
//  Timing contract
//   * published values change only at frame_tick;
//   * stage B publishes 3 clocks after frame_tick, stage A 10 clocks after it,
//     both inside vertical blanking; consumers latch at frame_done (4 clocks
//     after frame_tick, see hdmi_mixer.v) so nobody samples the previous frame;
//   * the mask box is the ROI published for the next frame (one frame of mask
//     latency, same as before).
// ============================================================================

// ----------------------------------------------------------------------------
// Per-pixel colour classifier.
//
//        chroma * 32  >=  value * 9        (S >= 28 %)
//        |G-B| * 8    <=  chroma * 6       (red hue within +-45 deg)
//        |R-G| * 8    <=  chroma * 6       (blue hue within +-45 deg)
//        value >= 96, chroma >= 20
// ----------------------------------------------------------------------------
module tracker_color_gate (
    input  wire [23:0] rgb,
    output wire red_hit,
    output wire blue_hit
);
    wire [7:0] r = rgb[23:16];
    wire [7:0] g = rgb[15:8];
    wire [7:0] b = rgb[7:0];

    wire [7:0] v = (r >= g) ? ((r >= b) ? r : b) : ((g >= b) ? g : b);
    wire [7:0] mn = (r <= g) ? ((r <= b) ? r : b) : ((g <= b) ? g : b);
    wire [7:0] chroma = v - mn;
    wire [7:0] gb = (g >= b) ? (g - b) : (b - g);
    wire [7:0] rg = (r >= g) ? (r - g) : (g - r);

    wire [12:0] c32 = {1'b0, chroma, 5'b00000};              // chroma*32
    wire [12:0] gb8 = {1'b0, gb, 3'b000};
    wire [12:0] rg8 = {1'b0, rg, 3'b000};
    wire [12:0] ch6 = {1'b0, chroma, 2'b00} + {1'b0, chroma, 1'b0};  // chroma*6
    wire [12:0] ch7 = {1'b0, chroma, 2'b00} + {1'b0, chroma, 1'b0} +
                      {1'b0, chroma};                                  // chroma*7

    // ======================================================================
    //  2026-11-03 (rev E)  --  light-adaptive colour gate
    //
    //  Field data from the HITS row:
    //    * in a dim room (empty scene)  R saturates at 999 while B stays 0,
    //    * in a bright room (empty scene) R and B are both near 0.
    //  That is the signature of *sensor noise*: with a fixed exposure the
    //  analogue gain is the same, but a dim scene is dominated by per-channel
    //  noise, so a grey wall dithers into "red" pixels by the thousand.  The
    //  region table is then full of wall clutter and the selection jumps
    //  between blobs - the "everything flickers when it gets darker" report.
    //
    //  A single absolute threshold cannot serve both regimes, so the gate is
    //  made light-adaptive: below V = 110 the chroma and saturation floors are
    //  raised to where noise cannot reach, above it they are relaxed.
    //
    //   red   bright: S >= 9/32  (28 %)   chroma >= 12   hue +-45 deg
    //         dim   : S >= 14/32 (44 %)   chroma >= 26   hue +-45 deg
    //   blue  bright: S >= 5/32  (16 %)   chroma >= 16   hue +-52 deg
    //         dim   : S >= 9/32  (28 %)   chroma >= 24   hue +-52 deg
    //
    //  The blue hue window is +-52 deg because the hand-painted blue disc is
    //  cyan-leaning (hue 210-215) while the moulded cap is 227; both are on the
    //  blue side of neutral, and with chroma >= 16 a neutral wall (chroma <= 8
    //  even with dither) still cannot pass.
    // ======================================================================
    wire dim = (v < 8'd110);
    wire [12:0] vr_s = dim ? ({1'b0, v, 3'b000} + {1'b0, v, 2'b00} + {1'b0, v, 1'b0})
                           : ({1'b0, v, 3'b000} + {1'b0, v});          // v*14 / v*9
    wire [12:0] vb_s = dim ? ({1'b0, v, 3'b000} + {1'b0, v})           // v*9
                           : ({1'b0, v, 2'b00} + {1'b0, v});           // v*5
    wire [7:0]  cr_floor = dim ? 8'd26 : 8'd12;
    wire [7:0]  cb_floor = dim ? 8'd24 : 8'd16;
    wire [12:0] ch7b = {1'b0, chroma, 2'b00} + {1'b0, chroma, 1'b0} +
                       {1'b0, chroma};                                 // chroma*7
    wire red_max = (r >= g) && (r >= b);
    wire blue_max = (b >= g) && (b >= r);

    assign red_hit = red_max && (v >= 8'd40) && (chroma >= cr_floor) &&
                     (c32 >= vr_s) && (gb8 <= ch6);
    assign blue_hit = blue_max && (v >= 8'd40) && (chroma >= cb_floor) &&
                      (c32 >= vb_s) && (rg8 <= ch7b);
endmodule

// Legacy four-colour entry point.  Green and yellow are not target classes in
// this build; they stay low so older wiring keeps compiling.
module tracker_hsv_mask (
    input  wire [23:0] rgb,
    output wire red_hit,
    output wire green_hit,
    output wire blue_hit,
    output wire yellow_hit
);
    tracker_color_gate u_gate(.rgb(rgb), .red_hit(red_hit), .blue_hit(blue_hit));
    assign green_hit = 1'b0;
    assign yellow_hit = 1'b0;
endmodule

// ----------------------------------------------------------------------------
// Stage A: streaming region table + ROI publication.
// ----------------------------------------------------------------------------
module tracker_region_channel #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer MIN_PIXELS = 48,
    parameter integer MIN_RUN = 5,
    parameter integer MIN_DIM = 8,
    parameter integer GAP = 6,
    parameter integer MARGIN = 14,
    parameter integer PREFER_CIRCLE = 1,
    parameter integer CENTER_X = 640,
    parameter integer CENTER_Y = 360
)(
    input  wire clk,
    input  wire rst_n,
    input  wire de,
    input  wire frame_tick,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire pixel_hit,
    output reg         roi_valid,
    output reg  [11:0] roi_left,
    output reg  [11:0] roi_right,
    output reg  [11:0] roi_top,
    output reg  [11:0] roi_bottom,
    output reg  [15:0] roi_pixels,
    output reg  [1:0]  roi_shape,
    output reg  [3:0]  instances,
    // Unpadded core box of the selected region; used by stage B as the corner
    // reference before the first refined box exists.
    output reg  [11:0] core_left,
    output reg  [11:0] core_right,
    output reg  [11:0] core_top,
    output reg  [11:0] core_bottom
);
    localparam integer MAXR = 4;
    localparam integer PIX_BITS = 20;

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_MUL  = 3'd1;   // register width/height/product
    localparam [2:0] ST_CMP  = 3'd2;   // gate + selection for one region
    localparam [2:0] ST_PUB  = 3'd3;   // publish ROI, clear table

    localparam [1:0] SH_OTHER = 2'd3;
    localparam [1:0] SH_CIRCLE = 2'd1;
    localparam [1:0] SH_RECT = 2'd2;

    reg             used [0:MAXR-1];
    reg [11:0]      rl [0:MAXR-1];
    reg [11:0]      rr [0:MAXR-1];
    reg [11:0]      rt [0:MAXR-1];
    reg [11:0]      rb [0:MAXR-1];
    reg [PIX_BITS-1:0] rp [0:MAXR-1];

    reg run_active;
    reg [11:0] run_l, run_r, run_y, run_len;
    reg [3:0] run_gap;

    reg [2:0] state;
    reg [1:0] sc_idx;
    reg [3:0] sc_inst;
    reg       sc_found;
    reg [3:0] sc_best_score;
    reg [12:0] sc_best_dist;
    reg [11:0] sc_bl, sc_br, sc_bt, sc_bb;
    reg [PIX_BITS-1:0] sc_bpix;
    reg [1:0] sc_bshape;

    // Registered per-region geometry for the two-cycle scan.
    reg [11:0] cw_r, ch_r;
    reg [23:0] cbox_r;
    reg [PIX_BITS-1:0] cpix_r;

    integer i;
    integer m, f, s;

    // Region table maintenance.  A run joins the first compatible region; a
    // long enough run that matches nothing opens a new region, and when the
    // table is full a region whose last hit is more than GAP+1 rows above the
    // current row is recycled instead of dropping the new run.
    task commit_run;
        begin
            m = -1;
            f = -1;
            s = -1;
            for (i = 0; i < MAXR; i = i + 1) begin
                if (!used[i] && (f < 0))
                    f = i;
                if (used[i] && (run_y > (rb[i] + GAP + 1)) && (s < 0))
                    s = i;
                if (used[i] && (m < 0) &&
                    (run_y >= rb[i]) && (run_y <= (rb[i] + GAP + 1)) &&
                    (run_l <= (rr[i] + GAP)) && ((run_r + GAP) >= rl[i]))
                    m = i;
            end
            if (m >= 0) begin
                if (run_l < rl[m]) rl[m] <= run_l;
                if (run_r > rr[m]) rr[m] <= run_r;
                rb[m] <= run_y;
                rp[m] <= rp[m] + {{(PIX_BITS-12){1'b0}}, run_len};
            end else if (run_len >= MIN_RUN) begin
                if (f >= 0) begin
                    used[f] <= 1'b1;
                    rl[f] <= run_l; rr[f] <= run_r;
                    rt[f] <= run_y; rb[f] <= run_y;
                    rp[f] <= {{(PIX_BITS-12){1'b0}}, run_len};
                end else if (s >= 0) begin
                    used[s] <= 1'b1;
                    rl[s] <= run_l; rr[s] <= run_r;
                    rt[s] <= run_y; rb[s] <= run_y;
                    rp[s] <= {{(PIX_BITS-12){1'b0}}, run_len};
                end
            end
        end
    endtask

    // Combinational view of region sc_idx.
    wire [11:0] cw = rr[sc_idx] - rl[sc_idx] + 1'b1;
    wire [11:0] ch = rb[sc_idx] - rt[sc_idx] + 1'b1;
    wire [23:0] cbox = cw * ch;
    wire [12:0] ccx = ({1'b0, rl[sc_idx]} + {1'b0, rr[sc_idx]}) >> 1;
    wire [12:0] ccy = ({1'b0, rt[sc_idx]} + {1'b0, rb[sc_idx]}) >> 1;
    wire [12:0] cdx = (ccx >= CENTER_X) ? (ccx - CENTER_X) : (CENTER_X - ccx);
    wire [12:0] cdy = (ccy >= CENTER_Y) ? (ccy - CENTER_Y) : (CENTER_Y - ccy);
    wire [13:0] cdist = cdx + cdy;

    // Fill ratio comparisons on the registered geometry (short paths).
    wire [26:0] p8  = {7'b0, cpix_r} << 3;                                 // pix*8
    wire [26:0] p16 = {7'b0, cpix_r} << 4;                                 // pix*16
    wire [26:0] b7  = ({7'b0, cbox_r} << 3) - {7'b0, cbox_r};              // box*7
    wire [26:0] b11 = ({7'b0, cbox_r} << 3) + ({7'b0, cbox_r} << 1) +
                      {7'b0, cbox_r};                                      // box*11
    wire fill_87 = (p8 >= b7);      // >= 87.5 %  -> rectangle evidence
    wire fill_68 = (p16 >= b11);    // >= 68.75 % -> circle evidence
    // Candidate gate raised from 43.75 % to 50 %: scattered noise clusters have
    // a low fill and used to occupy the four region slots in a dim room.
    wire fill_50 = (p16 >= {7'b0, cbox_r, 3'b000});   // pix*16 >= box*16 -> 50 %

    wire [12:0] cw5 = {1'b0, cw_r} * 13'd5;
    wire [12:0] ch5 = {1'b0, ch_r} * 13'd5;
    wire [13:0] cw8 = {2'b00, cw_r} * 14'd8;
    wire [13:0] ch8 = {2'b00, ch_r} * 14'd8;
    wire near_square = (cw5 <= ch8) && (ch5 <= cw8);
    wire wide = (cw_r > (ch_r * 3)) || (ch_r > (cw_r * 3));

    wire region_ok = used[sc_idx] &&
                     (cpix_r >= MIN_PIXELS) &&
                     (cw_r >= MIN_DIM) && (ch_r >= MIN_DIM) &&
                     !wide && fill_50;

    wire [1:0] region_shape = (fill_87 || (cw_r > (ch_r * 2)) ||
                               (ch_r > (cw_r * 2))) ? SH_RECT :
                              (near_square && fill_68) ? SH_CIRCLE : SH_OTHER;

    // Selection: a *large* object beats a small one, then a round one, then the
    // one closer to the crosshair.  Ranking by area first is what stops a dim
    // room from making the panel jump between small wall-noise blobs while a
    // real 20 k-pixel paper sits in front of the camera.
    wire [1:0] area_class = (cpix_r >= 20'd4096) ? 2'd3 :
                            (cpix_r >= 20'd1024) ? 2'd2 :
                            (cpix_r >= 20'd128)  ? 2'd1 : 2'd0;
    wire [3:0] region_score = {area_class,
                               ((PREFER_CIRCLE != 0) && (region_shape == SH_CIRCLE)),
                               fill_68};

    wire better = !sc_found ||
                  (region_score > sc_best_score) ||
                  ((region_score == sc_best_score) && (cdist[12:0] < sc_best_dist));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            run_active <= 1'b0;
            run_l <= 0; run_r <= 0; run_y <= 0; run_len <= 0; run_gap <= 0;
            roi_valid <= 1'b0;
            roi_left <= 0; roi_right <= 0; roi_top <= 0; roi_bottom <= 0;
            roi_pixels <= 0; roi_shape <= 0; instances <= 0;
            core_left <= 0; core_right <= 0; core_top <= 0; core_bottom <= 0;
            sc_idx <= 0; sc_inst <= 0; sc_found <= 0;
            sc_best_score <= 0; sc_best_dist <= 0;
            sc_bl <= 0; sc_br <= 0; sc_bt <= 0; sc_bb <= 0;
            sc_bpix <= 0; sc_bshape <= 0;
            cw_r <= 0; ch_r <= 0; cbox_r <= 0; cpix_r <= 0;
            for (i = 0; i < MAXR; i = i + 1) begin
                used[i] <= 1'b0;
                rl[i] <= 0; rr[i] <= 0; rt[i] <= 0; rb[i] <= 0;
                rp[i] <= 0;
            end
        end else begin
            if (frame_tick) begin
                if (run_active) begin
                    commit_run;
                    run_active <= 1'b0;
                    run_gap <= 0;
                end
                state <= ST_MUL;
                sc_idx <= 0;
                sc_inst <= 0;
                sc_found <= 1'b0;
                sc_best_score <= 0;
                sc_best_dist <= 14'h1fff;
            end else begin
                case (state)
                    ST_MUL: begin
                        cw_r <= cw;
                        ch_r <= ch;
                        cbox_r <= cbox;
                        cpix_r <= rp[sc_idx];
                        state <= ST_CMP;
                    end
                    ST_CMP: begin
                        if (region_ok) begin
                            sc_inst <= sc_inst + 1'b1;
                            if (better) begin
                                sc_found <= 1'b1;
                                sc_best_score <= region_score;
                                sc_best_dist <= cdist[12:0];
                                sc_bl <= rl[sc_idx];
                                sc_br <= rr[sc_idx];
                                sc_bt <= rt[sc_idx];
                                sc_bb <= rb[sc_idx];
                                sc_bpix <= rp[sc_idx];
                                sc_bshape <= region_shape;
                            end
                        end
                        if (sc_idx == (MAXR - 1)) begin
                            state <= ST_PUB;
                        end else begin
                            sc_idx <= sc_idx + 1'b1;
                            state <= ST_MUL;
                        end
                    end
                    ST_PUB: begin
                        roi_valid <= sc_found;
                        if (sc_found) begin
                            roi_left <= (sc_bl > MARGIN) ? (sc_bl - MARGIN) : 12'd0;
                            roi_right <= ((sc_br + MARGIN) < (WIDTH - 1)) ?
                                         (sc_br + MARGIN) : (WIDTH - 1);
                            roi_top <= (sc_bt > MARGIN) ? (sc_bt - MARGIN) : 12'd0;
                            roi_bottom <= ((sc_bb + MARGIN) < (HEIGHT - 1)) ?
                                          (sc_bb + MARGIN) : (HEIGHT - 1);
                            roi_pixels <= (sc_bpix > 16'hffff) ? 16'hffff :
                                          sc_bpix[15:0];
                            roi_shape <= sc_bshape;
                            core_left <= sc_bl;
                            core_right <= sc_br;
                            core_top <= sc_bt;
                            core_bottom <= sc_bb;
                        end else begin
                            roi_left <= 0; roi_right <= 0;
                            roi_top <= 0; roi_bottom <= 0;
                            roi_pixels <= 0; roi_shape <= 0;
                            core_left <= 0; core_right <= 0;
                            core_top <= 0; core_bottom <= 0;
                        end
                        instances <= sc_inst;
                        for (i = 0; i < MAXR; i = i + 1) begin
                            used[i] <= 1'b0;
                            rp[i] <= 0;
                        end
                        state <= ST_IDLE;
                    end
                    default: begin
                        if (de) begin
                            if (!run_active) begin
                                if (pixel_hit) begin
                                    run_active <= 1'b1;
                                    run_l <= x; run_r <= x; run_y <= y;
                                    run_len <= 12'd1; run_gap <= 4'd0;
                                end
                            end else if (y != run_y) begin
                                commit_run;
                                run_active <= 1'b0;
                                run_gap <= 4'd0;
                                if (pixel_hit) begin
                                    run_active <= 1'b1;
                                    run_l <= x; run_r <= x; run_y <= y;
                                    run_len <= 12'd1;
                                end
                            end else if (pixel_hit) begin
                                if (x <= (run_r + GAP + 1)) begin
                                    run_r <= x;
                                    run_len <= run_len + 1'b1;
                                    run_gap <= 4'd0;
                                end else begin
                                    commit_run;
                                    run_l <= x; run_r <= x; run_y <= y;
                                    run_len <= 12'd1; run_gap <= 4'd0;
                                end
                            end else if (run_gap < GAP) begin
                                run_gap <= run_gap + 1'b1;
                            end else begin
                                commit_run;
                                run_active <= 1'b0;
                                run_gap <= 4'd0;
                            end
                        end else if (run_active) begin
                            commit_run;
                            run_active <= 1'b0;
                            run_gap <= 4'd0;
                        end
                    end
                endcase
            end
        end
    end
endmodule

// ----------------------------------------------------------------------------
// Stage B: measure the published ROI only, publish the compact result.
//
//  * compact box and centre of everything that matched inside the ROI;
//  * area = hit count inside the ROI (16 bit, no 8191 clamp);
//  * shape from the four corner cells of the ROI (rectangle fills them, a
//    circle leaves them nearly empty) with a two-frame confirm;
//  * one frame of hold so a single bad frame does not drop the lock.
// ----------------------------------------------------------------------------
module tracker_roi_refine #(
    parameter integer MIN_PIXELS = 32,
    parameter integer MIN_CORNER_DIM = 64,
    parameter integer HOLD_FRAMES = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire de,
    input  wire frame_tick,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire pixel_hit,
    input  wire roi_valid,
    input  wire [11:0] roi_left,
    input  wire [11:0] roi_right,
    input  wire [11:0] roi_top,
    input  wire [11:0] roi_bottom,
    input  wire [15:0] roi_pixels,
    input  wire [1:0]  roi_shape,
    input  wire [11:0] core_left,
    input  wire [11:0] core_right,
    input  wire [11:0] core_top,
    input  wire [11:0] core_bottom,
    output reg         valid,
    output reg  [11:0] left,
    output reg  [11:0] right,
    output reg  [11:0] top,
    output reg  [11:0] bottom,
    output reg  [11:0] cx,
    output reg  [11:0] cy,
    output reg  [15:0] area,
    output reg  [1:0]  shape,
    output reg  [7:0]  confidence
);
    localparam integer PIX_BITS = 20;
    localparam [1:0] SH_OTHER = 2'd3;
    localparam [1:0] SH_CIRCLE = 2'd1;
    localparam [1:0] SH_RECT = 2'd2;
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_CAP  = 2'd1;
    localparam [1:0] ST_MUL  = 2'd2;
    localparam [1:0] ST_PUB  = 2'd3;

    reg in_roi;
    always @* begin
        in_roi = roi_valid &&
                 (x >= roi_left) && (x <= roi_right) &&
                 (y >= roi_top) && (y <= roi_bottom);
    end

    // Corner reference cells are taken from the ROI snapshot, because the
    // measured box is only known at the end of the frame.
    reg [11:0] cx1, cx2, cy1, cy2;   // quarter separators of the snapshot ROI

    reg [PIX_BITS-1:0] cnt;
    reg [11:0] ml, mr, mt, mb;
    reg [PIX_BITS-1:0] c_tl, c_tr, c_bl, c_br;

    reg [PIX_BITS-1:0] q_cnt;
    reg [11:0] q_ml, q_mr, q_mt, q_mb;
    reg [PIX_BITS-1:0] q_tl, q_tr, q_bl, q_br;
    reg        q_roi_valid;
    reg [11:0] q_roi_l, q_roi_r, q_roi_t, q_roi_b;
    reg [15:0] q_roi_pixels;
    reg [1:0]  q_roi_shape;

    reg [1:0] state;
    reg [1:0] hold;
    reg [11:0] bw, bh;
    reg [23:0] bbox;
    reg [PIX_BITS-1:0] bcnt;
    reg [11:0] bl, br, bt, bb;
    reg        b_have;
    reg [1:0]  b_shape_hint;
    reg [1:0]  shape_pending;
    reg        shape_pending_valid;

// removed duplicate (renamed below)
// removed duplicate (renamed below)
    wire [13:0] bw8 = {2'b00, bw} * 14'd8;
    wire [13:0] bh8 = {2'b00, bh} * 14'd8;
// removed duplicate (renamed below)
    // Corner cells are one eighth of the box per side, so a cell is 1/64 of the
    // box area.  For an inscribed circle the cell sits entirely outside the disc
    // (0 % coverage), for an axis-aligned rectangle it is completely inside.
    // A *slightly rotated* rectangle has empty bbox corners as well, so the
    // corner test alone cannot separate it from a circle: the fill ratio has to
    // help.  Measured on synthetic shapes (400x400 grid):
    //
    //   circle r70                  fill 0.773   min corner 1/8  0.00
    //   hand-cut decagon            fill 0.768   0.00
    //   circle with 20 % flat cut   fill 0.818   0.00
    //   square 200x200 @5 deg       fill 0.849   0.38
    //   rect 200x140 @5 deg         fill 0.845   0.14
    //   rect 200x140 @0 deg         fill 1.000   1.00
    //
    // Decision:
    //   CIRCLE when near-square, fill <= 0.82 and all four corners <= 10 %
    //   RECT   when fill >= 0.84, or all four corners >= 20 %, or aspect >= 2
    //   else OTHER
    // The corner part is only used when the box is at least MIN_CORNER_DIM so
    // that a small target cannot be mislabelled by a 2x2 pixel cell.
    wire [35:0] qtl = {16'b0, q_tl[19:0]};
    wire [35:0] qtr = {16'b0, q_tr[19:0]};
    wire [35:0] qbl = {16'b0, q_bl[19:0]};
    wire [35:0] qbr = {16'b0, q_br[19:0]};
    wire [35:0] box36 = {12'b0, bbox};
    wire [35:0] c800_tl = qtl * 36'd800;      // c*800 <= box  -> cell <= 8 %
    wire [35:0] c800_tr = qtr * 36'd800;
    wire [35:0] c800_bl = qbl * 36'd800;
    wire [35:0] c800_br = qbr * 36'd800;
    wire [35:0] c512_tl = qtl * 36'd512;      // c*512 >= box  -> cell >= 12.5 %
    wire [35:0] c512_tr = qtr * 36'd512;
    wire [35:0] c512_bl = qbl * 36'd512;
    wire [35:0] c512_br = qbr * 36'd512;
    wire small_box = (bw < MIN_CORNER_DIM) || (bh < MIN_CORNER_DIM);
    wire corners_low  = (c800_tl <= box36) && (c800_tr <= box36) &&
                        (c800_bl <= box36) && (c800_br <= box36);
    wire corners_high = (c512_tl >= box36) && (c512_tr >= box36) &&
                        (c512_bl >= box36) && (c512_br >= box36);

    // Fill ratio: 0.82 = 41/50 (small-box circle), 0.90 = 9/10 (small-box rectangle).
    wire [26:0] c50 = {7'b0, bcnt} * 27'd50;
    wire [26:0] b41 = {3'b0, bbox} * 27'd41;
    wire [26:0] c9  = {8'b0, bcnt} * 27'd9;
    wire [26:0] b10 = {3'b0, bbox} * 27'd10;
    wire fill_lo = (c50 <= b41);        // fill <= 0.82
    wire fill_hi = (c9 >= b10);         // fill >= 0.90
    wire [7:0] fill_conf = fill_hi ? 8'd96 : fill_lo ? 8'd88 : 8'd80;

    // Shape decision (rev D).  The previous rules tried to separate a circle
    // from a *rotated* rectangle with bbox-corner occupancy, but a hand-held
    // rectangle is always rotated a few degrees and then its bbox corners are
    // empty too (measured: 1.5:1 rect @8 deg -> fill 0.65, min corner 0 %),
    // so it fell through to OTHER or CIRCLE.  The robust, rotation-invariant
    // separator is the *aspect ratio of the bbox* combined with the fill:
    //
    //   circle   : bbox is square (aspect <= 1.3) and fill <= 0.82
    //              (an inscribed disc fills pi/4 = 0.785; rotation does not
    //              change a disc's bbox at all)
    //   rectangle: anything else that is reasonably filled (>= 0.56);
    //              a 1.5:1 rectangle keeps aspect 1.4..1.7 at any tilt, and a
    //              square keeps fill ~1.0 when axis aligned (>= 0.82)
    //   OTHER    : too sparse / heavily occluded
    //
    // The corner cells are kept as extra evidence for the circle case only
    // when the box is large enough for them to mean something.
    wire [13:0] bw10 = {2'b00, bw} * 14'd10;
    wire [13:0] bh10 = {2'b00, bh} * 14'd10;
    wire [13:0] bw13 = {2'b00, bw} * 14'd13;
    wire [13:0] bh13 = {2'b00, bh} * 14'd13;
    wire [27:0] c16 = {8'b0, bcnt} * 28'd16;
    wire [27:0] b9  = {4'b0, bbox} * 28'd9;
    wire near_square = (bw10 <= bh13) && (bh10 <= bw13);     // aspect <= 1.3
    wire fill_ok = (c16 >= b9);                              // fill >= 0.5625

    wire circle_case = near_square && fill_lo && (small_box || corners_low);
    wire rect_case = fill_ok;
    wire [1:0] corner_shape = circle_case ? SH_CIRCLE :
                              rect_case ? SH_RECT : SH_OTHER;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0; ml <= 0; mr <= 0; mt <= 0; mb <= 0;
            c_tl <= 0; c_tr <= 0; c_bl <= 0; c_br <= 0;
            cx1 <= 0; cx2 <= 0; cy1 <= 0; cy2 <= 0;
            q_cnt <= 0; q_ml <= 0; q_mr <= 0; q_mt <= 0; q_mb <= 0;
            q_tl <= 0; q_tr <= 0; q_bl <= 0; q_br <= 0;
            q_roi_valid <= 1'b0; q_roi_l <= 0; q_roi_r <= 0;
            q_roi_t <= 0; q_roi_b <= 0; q_roi_pixels <= 0; q_roi_shape <= 0;
            state <= ST_IDLE;
            hold <= 0;
            bw <= 0; bh <= 0; bbox <= 0; bcnt <= 0;
            bl <= 0; br <= 0; bt <= 0; bb <= 0;
            b_have <= 1'b0; b_shape_hint <= 0;
            shape_pending <= 0; shape_pending_valid <= 1'b0;
            valid <= 1'b0;
            left <= 0; right <= 0; top <= 0; bottom <= 0;
            cx <= 0; cy <= 0; area <= 0; shape <= 0; confidence <= 0;
        end else begin
            if (frame_tick) begin
                q_cnt <= cnt;
                q_ml <= ml; q_mr <= mr; q_mt <= mt; q_mb <= mb;
                q_tl <= c_tl; q_tr <= c_tr; q_bl <= c_bl; q_br <= c_br;
                q_roi_valid <= roi_valid;
                q_roi_l <= roi_left; q_roi_r <= roi_right;
                q_roi_t <= roi_top; q_roi_b <= roi_bottom;
                q_roi_pixels <= roi_pixels; q_roi_shape <= roi_shape;
                // Corner cells follow the last published tight box, because the
                // ROI carries a margin that would dilute the corner test.  On
                // the first frame after acquisition the unpadded stage A core
                // box is used, and only if that is missing the padded ROI.
                if (valid && (right > left) && (bottom > top)) begin
                    cx1 <= left + ((right - left) >> 3);
                    cx2 <= right - ((right - left) >> 3);
                    cy1 <= top + ((bottom - top) >> 3);
                    cy2 <= bottom - ((bottom - top) >> 3);
                end else if ((core_right > core_left) && (core_bottom > core_top)) begin
                    cx1 <= core_left + ((core_right - core_left) >> 3);
                    cx2 <= core_right - ((core_right - core_left) >> 3);
                    cy1 <= core_top + ((core_bottom - core_top) >> 3);
                    cy2 <= core_bottom - ((core_bottom - core_top) >> 3);
                end else begin
                    cx1 <= roi_left + ((roi_right - roi_left) >> 3);
                    cx2 <= roi_right - ((roi_right - roi_left) >> 3);
                    cy1 <= roi_top + ((roi_bottom - roi_top) >> 3);
                    cy2 <= roi_bottom - ((roi_bottom - roi_top) >> 3);
                end
                cnt <= 0;
                c_tl <= 0; c_tr <= 0; c_bl <= 0; c_br <= 0;
                state <= ST_CAP;
            end else begin
                if (de && in_roi && pixel_hit) begin
                    if (cnt == 0) begin
                        ml <= x; mr <= x; mt <= y; mb <= y;
                    end else begin
                        if (x < ml) ml <= x;
                        if (x > mr) mr <= x;
                        if (y < mt) mt <= y;
                        if (y > mb) mb <= y;
                    end
                    cnt <= cnt + 1'b1;
                    if ((x <= cx1) && (y <= cy1)) c_tl <= c_tl + 1'b1;
                    if ((x >= cx2) && (y <= cy1)) c_tr <= c_tr + 1'b1;
                    if ((x <= cx1) && (y >= cy2)) c_bl <= c_bl + 1'b1;
                    if ((x >= cx2) && (y >= cy2)) c_br <= c_br + 1'b1;
                end

                case (state)
                    ST_CAP: begin
                        if (q_cnt >= MIN_PIXELS) begin
                            bl <= q_ml; br <= q_mr; bt <= q_mt; bb <= q_mb;
                            bcnt <= q_cnt;
                            b_have <= 1'b1;
                            b_shape_hint <= 2'd0;
                        end else if (q_roi_valid) begin
                            // Nothing matched inside the ROI this frame: keep the
                            // ROI for one frame so the lock does not drop.
                            bl <= q_roi_l; br <= q_roi_r;
                            bt <= q_roi_t; bb <= q_roi_b;
                            bcnt <= {{(PIX_BITS-16){1'b0}}, q_roi_pixels};
                            b_have <= 1'b1;
                            b_shape_hint <= q_roi_shape;
                        end else begin
                            bl <= 0; br <= 0; bt <= 0; bb <= 0;
                            bcnt <= 0;
                            b_have <= 1'b0;
                            b_shape_hint <= 2'd0;
                        end
                        state <= ST_MUL;
                    end
                    ST_MUL: begin
                        bw <= br - bl + 1'b1;
                        bh <= bb - bt + 1'b1;
                        bbox <= (br - bl + 1'b1) * (bb - bt + 1'b1);
                        state <= ST_PUB;
                    end
                    ST_PUB: begin
                        if (b_have && (bcnt != 0) && (bw >= 2) && (bh >= 2)) begin
                            valid <= 1'b1;
                            hold <= 0;
                            left <= bl;
                            right <= br;
                            top <= bt;
                            bottom <= bb;
                            cx <= ({1'b0, bl} + {1'b0, br}) >> 1;
                            cy <= ({1'b0, bt} + {1'b0, bb}) >> 1;
                            area <= (bcnt > 16'hffff) ? 16'hffff : bcnt[15:0];
                            // Shape:
                            //  * ROI fallback (no hits this frame) republishes the
                            //    coarse stage A class directly;
                            //  * a real measurement is confirmed over two frames so
                            //    brush texture cannot flicker the label.  For a box
                            //    smaller than MIN_CORNER_DIM the corner cells are
                            //    not trustworthy and the fill ratio decides.
                            if (b_shape_hint != 2'd0) begin
                                shape <= b_shape_hint;
                                shape_pending_valid <= 1'b0;
                            end else begin
                                if ((shape_pending_valid) &&
                                    (corner_shape == shape_pending)) begin
                                    shape <= corner_shape;
                                    shape_pending_valid <= 1'b0;
                                end else if (corner_shape != shape) begin
                                    shape_pending <= corner_shape;
                                    shape_pending_valid <= 1'b1;
                                end else begin
                                    shape_pending_valid <= 1'b0;
                                end
                            end
                            confidence <= (b_shape_hint != 2'd0) ? 8'd70 : fill_conf;
                        end else if (valid && (hold < HOLD_FRAMES)) begin
                            hold <= hold + 1'b1;
                        end else begin
                            valid <= 1'b0;
                            confidence <= 8'd0;
                            hold <= 0;
                            shape_pending_valid <= 1'b0;
                        end
                        state <= ST_IDLE;
                    end
                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule

// ----------------------------------------------------------------------------
// Target-only sparse mask: the selected target's box and its colour hits.
// ----------------------------------------------------------------------------
module tracker_target_mask_gate (
    input  wire source_alive,
    input  wire target_valid,
    input  wire color_hit,
    input  wire [11:0] x, y,
    input  wire [11:0] left, right, top, bottom,
    output wire mask_hit
);
    assign mask_hit = source_alive && target_valid && color_hit &&
                      (x >= left) && (x <= right) &&
                      (y >= top) && (y <= bottom);
endmodule

// Legacy gates kept so older unit tests keep elaborating.
module tracker_mask_region_gate (
    input wire source_alive,
    input wire candidate_valid,
    input wire color_hit,
    input wire region_hit,
    output wire mask_hit
);
    assign mask_hit = source_alive && candidate_valid && color_hit && region_hit;
endmodule

module tracker_mask_gate (
    input wire source_alive,
    input wire candidate_valid,
    input wire color_hit,
    input wire [11:0] x, y,
    input wire [11:0] left, right, top, bottom,
    output wire mask_hit
);
    assign mask_hit = source_alive && candidate_valid && color_hit &&
                      x >= left && x <= right && y >= top && y <= bottom;
endmodule

// ----------------------------------------------------------------------------
// Top level: two colour channels, each with a stage A and a stage B.
// ----------------------------------------------------------------------------
module tracker_candidates #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer MIN_PIXELS = 48,
    parameter integer MIN_RUN = 5,
    parameter integer MIN_DIM = 8,
    parameter integer GAP = 6,
    parameter integer MARGIN = 14,
    parameter integer CENTER_X = WIDTH/2,
    parameter integer CENTER_Y = HEIGHT/2
)(
    input wire clk, rst_n, de, frame_tick,
    input wire [11:0] x, y,
    input wire [23:0] rgb,
    output wire red_valid, green_valid, blue_valid, yellow_valid,
    output wire [11:0] red_left, red_right, red_top, red_bottom, red_cx, red_cy,
    output wire [11:0] green_left, green_right, green_top, green_bottom, green_cx, green_cy,
    output wire [11:0] blue_left, blue_right, blue_top, blue_bottom, blue_cx, blue_cy,
    output wire [11:0] yellow_left, yellow_right, yellow_top, yellow_bottom, yellow_cx, yellow_cy,
    output wire [15:0] red_area, green_area, blue_area, yellow_area,
    output wire [1:0] red_shape, green_shape, blue_shape, yellow_shape,
    output wire [7:0] red_confidence, green_confidence, blue_confidence, yellow_confidence,
    output wire [3:0] red_instances, green_instances, blue_instances, yellow_instances,
    // Mask box: the ROI published for the next frame.
    output wire [11:0] red_mask_left, red_mask_right, red_mask_top, red_mask_bottom,
    output wire [11:0] blue_mask_left, blue_mask_right, blue_mask_top, blue_mask_bottom,
    // Per-pixel classification results for the mask gate and binary view.
    output wire red_hsv_hit, green_hsv_hit, blue_hsv_hit, yellow_hsv_hit,
    // Colour hit counts of the last frame (saturated at 999).  This is the only
    // diagnostic that separates "the colour test never fires" from "the region
    // or selection stage dropped it"; it drives the HITS row of the panel.
    output wire [9:0] red_hits, blue_hits
);
    wire red_hit, blue_hit;

    tracker_color_gate u_colour_gate(
        .rgb(rgb), .red_hit(red_hit), .blue_hit(blue_hit));

    reg [9:0] red_cnt, blue_cnt, red_cnt_pub, blue_cnt_pub;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            red_cnt <= 10'd0; blue_cnt <= 10'd0;
            red_cnt_pub <= 10'd0; blue_cnt_pub <= 10'd0;
        end else if (frame_tick) begin
            red_cnt_pub <= red_cnt;
            blue_cnt_pub <= blue_cnt;
            red_cnt <= 10'd0;
            blue_cnt <= 10'd0;
        end else if (de) begin
            if (red_hit && (red_cnt < 10'd999)) red_cnt <= red_cnt + 1'b1;
            if (blue_hit && (blue_cnt < 10'd999)) blue_cnt <= blue_cnt + 1'b1;
        end
    end
    assign red_hits = red_cnt_pub;
    assign blue_hits = blue_cnt_pub;

    // ---- red channel -------------------------------------------------------
    wire        red_roi_valid;
    wire [11:0] red_roi_l, red_roi_r, red_roi_t, red_roi_b;
    wire [15:0] red_roi_pix;
    wire [1:0]  red_roi_shape;
    wire [11:0] red_core_l, red_core_r, red_core_t, red_core_b;

    tracker_region_channel #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .MIN_PIXELS(MIN_PIXELS), .MIN_RUN(MIN_RUN), .MIN_DIM(MIN_DIM),
        .GAP(GAP), .MARGIN(MARGIN),
        .PREFER_CIRCLE(1),
        .CENTER_X(CENTER_X), .CENTER_Y(CENTER_Y)) red_region (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .pixel_hit(red_hit),
        .roi_valid(red_roi_valid),
        .roi_left(red_roi_l), .roi_right(red_roi_r),
        .roi_top(red_roi_t), .roi_bottom(red_roi_b),
        .roi_pixels(red_roi_pix), .roi_shape(red_roi_shape),
        .core_left(red_core_l), .core_right(red_core_r), .core_top(red_core_t), .core_bottom(red_core_b),
        .instances(red_instances));

    tracker_roi_refine red_refine (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .pixel_hit(red_hit),
        .roi_valid(red_roi_valid),
        .roi_left(red_roi_l), .roi_right(red_roi_r),
        .roi_top(red_roi_t), .roi_bottom(red_roi_b),
        .roi_pixels(red_roi_pix), .roi_shape(red_roi_shape),
        .core_left(red_core_l), .core_right(red_core_r), .core_top(red_core_t), .core_bottom(red_core_b),
        .valid(red_valid),
        .left(red_left), .right(red_right), .top(red_top), .bottom(red_bottom),
        .cx(red_cx), .cy(red_cy), .area(red_area), .shape(red_shape),
        .confidence(red_confidence));

    assign red_mask_left = red_roi_l;
    assign red_mask_right = red_roi_r;
    assign red_mask_top = red_roi_t;
    assign red_mask_bottom = red_roi_b;

    // ---- blue channel ------------------------------------------------------
    wire        blue_roi_valid;
    wire [11:0] blue_roi_l, blue_roi_r, blue_roi_t, blue_roi_b;
    wire [15:0] blue_roi_pix;
    wire [1:0]  blue_roi_shape;
    wire [11:0] blue_core_l, blue_core_r, blue_core_t, blue_core_b;

    tracker_region_channel #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .MIN_PIXELS(MIN_PIXELS), .MIN_RUN(MIN_RUN), .MIN_DIM(MIN_DIM),
        .GAP(GAP), .MARGIN(MARGIN),
        .PREFER_CIRCLE(0),
        .CENTER_X(CENTER_X), .CENTER_Y(CENTER_Y)) blue_region (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .pixel_hit(blue_hit),
        .roi_valid(blue_roi_valid),
        .roi_left(blue_roi_l), .roi_right(blue_roi_r),
        .roi_top(blue_roi_t), .roi_bottom(blue_roi_b),
        .roi_pixels(blue_roi_pix), .roi_shape(blue_roi_shape),
        .core_left(blue_core_l), .core_right(blue_core_r), .core_top(blue_core_t), .core_bottom(blue_core_b),
        .instances(blue_instances));

    tracker_roi_refine blue_refine (
        .clk(clk), .rst_n(rst_n), .de(de), .frame_tick(frame_tick),
        .x(x), .y(y), .pixel_hit(blue_hit),
        .roi_valid(blue_roi_valid),
        .roi_left(blue_roi_l), .roi_right(blue_roi_r),
        .roi_top(blue_roi_t), .roi_bottom(blue_roi_b),
        .roi_pixels(blue_roi_pix), .roi_shape(blue_roi_shape),
        .core_left(blue_core_l), .core_right(blue_core_r), .core_top(blue_core_t), .core_bottom(blue_core_b),
        .valid(blue_valid),
        .left(blue_left), .right(blue_right), .top(blue_top), .bottom(blue_bottom),
        .cx(blue_cx), .cy(blue_cy), .area(blue_area), .shape(blue_shape),
        .confidence(blue_confidence));

    assign blue_mask_left = blue_roi_l;
    assign blue_mask_right = blue_roi_r;
    assign blue_mask_top = blue_roi_t;
    assign blue_mask_bottom = blue_roi_b;

    // ---- green / yellow stay disabled in this build ------------------------
    assign green_valid = 1'b0;
    assign green_left = 0; assign green_right = 0;
    assign green_top = 0; assign green_bottom = 0;
    assign green_cx = 0; assign green_cy = 0;
    assign green_area = 0; assign green_shape = 0;
    assign green_confidence = 0; assign green_instances = 0;

    assign yellow_valid = 1'b0;
    assign yellow_left = 0; assign yellow_right = 0;
    assign yellow_top = 0; assign yellow_bottom = 0;
    assign yellow_cx = 0; assign yellow_cy = 0;
    assign yellow_area = 0; assign yellow_shape = 0;
    assign yellow_confidence = 0; assign yellow_instances = 0;

    assign red_hsv_hit = red_hit;
    assign blue_hsv_hit = blue_hit;
    assign green_hsv_hit = 1'b0;
    assign yellow_hsv_hit = 1'b0;
endmodule
