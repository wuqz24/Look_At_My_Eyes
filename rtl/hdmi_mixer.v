module hdmi_mixer #(
    parameter H_OFFSET=0, V_OFFSET=0, IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer DEBUG_MODE=0,
    parameter integer COLOR_REFERENCE=0,
    parameter integer PIXEL_HZ=75000000,
    parameter integer SERVO_SELFTEST_HOLD_MS=250
)(
    input wire I_clk,I_rst_n,I_video_vsync,I_video_hsync,I_video_de,I_video_user,I_video_last,
    input wire [3:0] I_debug_status,
    input wire I_mode_n,I_color_n,I_arm_n,I_capture_toggle,
    input wire I_sw1,I_sw2,
    output wire O_pan_pwm,O_tilt_pwm,O_buzzer,
    output wire [31:0] O_time_gray,
    output wire O_video_rd_en,
    input wire [23:0] I_video_rd_data,
    output reg O_hdmi_vsync,O_hdmi_hsync,O_hdmi_de,
    output reg [23:0] O_hdmi_data
);
    // Active-video center. The crosshair and every target-distance decision
    // use these exact coordinates, so the reference point is the visible
    // center of the 1280x720 image rather than the upper-left origin.
    localparam integer CENTER_X = IMG_WIDTH/2;
    localparam integer CENTER_Y = IMG_HEIGHT/2;
    reg [1:0] rst_sync;
    wire reset_n=rst_sync[1];
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) rst_sync<=0; else rst_sync<={rst_sync[0],1'b1};
    assign O_video_rd_en=I_video_de;
    reg [1:0] de_d,vs_d,hs_d;
    // I_video_rd_data is already returned by the external two-cycle DDR read
    // path. Consume it alongside de_d[1] and x/y without adding another delay.
    reg [11:0] x,y;
    reg de_prev, active_line_seen;
    reg vs_prev;
    wire line_start=de_d[1] && !de_prev;
    wire [11:0] pixel_y=(line_start && active_line_seen && y<IMG_HEIGHT-1) ? y+1'b1 : y;
    wire frame_tick=vs_d[1] && !vs_prev;
    // Every consumer that latches the published analysis result samples it
    // through frame_done.  Stage B publishes three clocks after frame_tick and
    // stage A ten clocks after it, so latching at frame_tick itself would take
    // the previous frame's value and add one full frame to the gimbal loop.
    reg [3:0] ft_d;
    always @(posedge I_clk or negedge reset_n)
        if(!reset_n) ft_d<=4'd0; else ft_d<={ft_d[2:0],frame_tick};
    wire frame_done=ft_d[3];
    reg [2:0] capture_sync;
    reg [31:0] age;
    reg [31:0] stream_age;
    wire tag_alive,tag_valid;
    wire [31:0] latency_us;
    wire video_healthy,video_recovery,video_fault;
    // The in-band tag is diagnostic only.  Older builds put the tag at a
    // different packed-pixel position than frame_tag_rx expects, so using it
    // as a hard gate can hold the detector and servo in reset forever.
    // Active video itself is the liveness source for the recognition path.
    wire source_alive=(stream_age < PIXEL_HZ/10);
    frame_tag_rx #(.CLK_HZ(PIXEL_HZ)) tag_rx(
        .clk(I_clk),.rst_n(reset_n),.de(de_d[1]),.x(x),.y(pixel_y),.rgb(I_video_rd_data),
        .time_gray(O_time_gray),.latency_us(latency_us),.alive(tag_alive),.tag_valid(tag_valid));
    video_health #(.CLK_HZ(PIXEL_HZ),.TIMEOUT_MS(120),.RECOVERY_FRAMES(2)) health(
        .clk(I_clk),.rst_n(reset_n),.frame_tick(frame_tick),.tag_alive(tag_alive),.tag_valid(tag_valid),
        .de(de_d[1]),.rgb_nonzero(|I_video_rd_data),.healthy(video_healthy),
        .recovery(video_recovery),.fault(video_fault));
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            de_d<=0; vs_d<=0; hs_d<=0; x<=0; y<=0; vs_prev<=0;
            de_prev<=0; active_line_seen<=0;
            capture_sync<=0; age<=PIXEL_HZ/10;
            stream_age<=PIXEL_HZ/10;
        end else begin
            de_d<={de_d[0],I_video_de}; vs_d<={vs_d[0],I_video_vsync}; hs_d<={hs_d[0],I_video_hsync};
            vs_prev<=vs_d[1]; capture_sync<={capture_sync[1:0],I_capture_toggle};
            if(capture_sync[2]!=capture_sync[1]) age<=0;
            else if(age<PIXEL_HZ/10) age<=age+1'b1;
            if(de_d[1] || frame_tick) stream_age<=0;
            else if(stream_age<PIXEL_HZ/10) stream_age<=stream_age+1'b1;
            de_prev<=de_d[1];
            if(frame_tick) begin
                x<=0;
                y<=0;
                active_line_seen<=1'b0;
            end else if(line_start) begin
                // The first active pixel is consumed on this edge. Preload
                // the following coordinate so later pixels are not one low.
                x<=12'd1;
                if(active_line_seen && y<IMG_HEIGHT-1)
                    y<=y+1'b1;
                active_line_seen<=1'b1;
            end else if(de_d[1]) begin
                if(x<IMG_WIDTH-1) x<=x+1'b1;
            end else begin
                x<=0;
            end
        end
    end
    wire [2:0] mode;
    wire [1:0] color,shape;
    wire armed,moving,valid,mvalid,hit,busy,overrun;
    wire [11:0] l,r,t,b,cx,cy,ml,mr,mt,mb,pan_us,tilt_us;
    wire [12:0] area;
    wire [31:0] cycles;
    wire red_valid,green_valid,blue_valid,yellow_valid;
    wire [11:0] red_l,red_r,red_t,red_b,red_cx,red_cy;
    wire [11:0] green_l,green_r,green_t,green_b,green_cx,green_cy;
    wire [11:0] blue_l,blue_r,blue_t,blue_b,blue_cx,blue_cy;
    wire [11:0] yellow_l,yellow_r,yellow_t,yellow_b,yellow_cx,yellow_cy;
    wire [15:0] red_area,green_area,blue_area,yellow_area;
    wire [1:0] red_shape,green_shape,blue_shape,yellow_shape;
    wire [7:0] red_confidence,green_confidence,blue_confidence,yellow_confidence;
    wire [3:0] red_instances,green_instances,blue_instances,yellow_instances;
    wire [11:0] red_ml,red_mr,red_mt,red_mb,blue_ml,blue_mr,blue_mt,blue_mb;
    wire red_loose_hit,blue_loose_hit,green_loose_hit,yellow_loose_hit;
    wire [9:0] red_hits,blue_hits;
    tracker_control #(.CLK_HZ(PIXEL_HZ),.USE_ARM_INPUT(0)) controls(
        .clk(I_clk),.rst_n(reset_n),.mode_n(I_mode_n),.color_n(I_color_n),.arm_n(I_arm_n),
        .frame_tick(frame_tick),.mode(mode),.color(color),.armed(armed));
    wire [23:0] rgb_display=I_video_rd_data;
    // The external DDR reader has already delayed the pixel to match de_d[1].
    wire [23:0] rgb_video=I_video_rd_data;

    tracker_candidates #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.CENTER_X(CENTER_X),.CENTER_Y(CENTER_Y)) candidates(
        .clk(I_clk),.rst_n(reset_n),.de(de_d[1]),
        .frame_tick(frame_tick),.x(x),.y(pixel_y),.rgb(rgb_video),
        .red_valid(red_valid),.green_valid(green_valid),.blue_valid(blue_valid),.yellow_valid(yellow_valid),
        .red_left(red_l),.red_right(red_r),.red_top(red_t),.red_bottom(red_b),.red_cx(red_cx),.red_cy(red_cy),
        .green_left(green_l),.green_right(green_r),.green_top(green_t),.green_bottom(green_b),.green_cx(green_cx),.green_cy(green_cy),
        .blue_left(blue_l),.blue_right(blue_r),.blue_top(blue_t),.blue_bottom(blue_b),.blue_cx(blue_cx),.blue_cy(blue_cy),
        .yellow_left(yellow_l),.yellow_right(yellow_r),.yellow_top(yellow_t),.yellow_bottom(yellow_b),
        .yellow_cx(yellow_cx),.yellow_cy(yellow_cy),
        .red_area(red_area),.green_area(green_area),.blue_area(blue_area),.yellow_area(yellow_area),
        .red_shape(red_shape),.green_shape(green_shape),.blue_shape(blue_shape),.yellow_shape(yellow_shape),
        .red_confidence(red_confidence),.green_confidence(green_confidence),
        .blue_confidence(blue_confidence),.yellow_confidence(yellow_confidence),
        .red_instances(red_instances),.green_instances(green_instances),
        .blue_instances(blue_instances),.yellow_instances(yellow_instances),
        .red_mask_left(red_ml),.red_mask_right(red_mr),.red_mask_top(red_mt),.red_mask_bottom(red_mb),
        .blue_mask_left(blue_ml),.blue_mask_right(blue_mr),.blue_mask_top(blue_mt),.blue_mask_bottom(blue_mb),
        .red_hsv_hit(red_loose_hit),.green_hsv_hit(green_loose_hit),
        .blue_hsv_hit(blue_loose_hit),.yellow_hsv_hit(yellow_loose_hit),
        .red_hits(red_hits),.blue_hits(blue_hits));

    // Which candidate the status panel and the mask show: the one closest to
    // the crosshair, whatever its colour.  This replaced the old "red always
    // wins if any red candidate exists" rule, which silently hid a centred blue
    // target whenever some red object was anywhere in the frame.  The colour
    // button is only a tie-break between equally close candidates.
    function [12:0] center_distance;
        input [11:0] px;
        input [11:0] py;
        integer dx_i;
        integer dy_i;
        begin
            dx_i = $signed({1'b0,px}) - CENTER_X;
            dy_i = $signed({1'b0,py}) - CENTER_Y;
            if(dx_i < 0) dx_i = -dx_i;
            if(dy_i < 0) dy_i = -dy_i;
            center_distance = dx_i + dy_i;
        end
    endfunction
    wire [12:0] red_dist  = center_distance(red_cx, red_cy);
    wire [12:0] blue_dist = center_distance(blue_cx, blue_cy);
    wire        pref_blue = (color == 2'd2);
    wire        sel_blue  = blue_valid && (!red_valid ||
                                           (blue_dist < red_dist) ||
                                           ((blue_dist == red_dist) && pref_blue));
    wire        tgt_valid     = sel_blue ? blue_valid : red_valid;
    wire [11:0] tgt_l         = sel_blue ? blue_l : red_l;
    wire [11:0] tgt_r         = sel_blue ? blue_r : red_r;
    wire [11:0] tgt_t         = sel_blue ? blue_t : red_t;
    wire [11:0] tgt_b         = sel_blue ? blue_b : red_b;
    wire [11:0] tgt_cx        = sel_blue ? blue_cx : red_cx;
    wire [11:0] tgt_cy        = sel_blue ? blue_cy : red_cy;
    wire [15:0] tgt_area      = sel_blue ? blue_area : red_area;
    wire [1:0]  tgt_shape     = sel_blue ? blue_shape : red_shape;
    wire [11:0] tgt_mask_l    = sel_blue ? blue_ml : red_ml;
    wire [11:0] tgt_mask_r    = sel_blue ? blue_mr : red_mr;
    wire [11:0] tgt_mask_t    = sel_blue ? blue_mt : red_mt;
    wire [11:0] tgt_mask_b    = sel_blue ? blue_mb : red_mb;
    wire        tgt_loose_hit = sel_blue ? blue_loose_hit : red_loose_hit;

    assign valid = source_alive && tgt_valid;
    assign l = tgt_l;
    assign r = tgt_r;
    assign t = tgt_t;
    assign b = tgt_b;
    assign cx = tgt_cx;
    assign cy = tgt_cy;
    assign area = tgt_area;
    assign shape = tgt_shape;
    assign hit = tgt_loose_hit;
    assign mvalid = valid;
    assign ml = l; assign mr = r;
    assign mt = t; assign mb = b;
    assign busy = 1'b0;
    assign overrun = 1'b0;
    assign cycles = 32'd0;

    // Gimbal target rule (as requested): follow **only a red CIRCLE**.  The
    // status panel and the mask may show a blue or rectangular object, but the
    // servo only moves for red circles, and it uses the red channel's centre
    // directly so a blue object in view can never pull the gimbal.
    wire track_candidate = red_valid && (red_shape == 2'd1) && (red_area >= 16'd64);
    reg [11:0] track_cx_latched,track_cy_latched;
    reg [1:0] track_stable_frames;
    reg [1:0] track_missed_frames;
    reg track_latched;
    reg [1:0] color_d;
    wire stable_target=track_latched;
    wire follow_enable=track_latched;
    // Qualify a new target briefly, then tolerate short detection dropouts.
    // A colour change clears the latch so the servo never chases the previous
    // class while the button debounce finishes.
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            track_stable_frames<=0;
            track_missed_frames<=0;
            track_latched<=1'b0;
            track_cx_latched<=0;
            track_cy_latched<=0;
            color_d<=2'd0;
        end else if(frame_done) begin
            color_d<=color;
            if(color_d != color) begin
                track_stable_frames<=0;
                track_missed_frames<=0;
                track_latched<=1'b0;
            end else if(source_alive && track_candidate) begin
                track_cx_latched<=red_cx;
                track_cy_latched<=red_cy;
                track_missed_frames<=0;
                if(track_stable_frames<3)
                    track_stable_frames<=track_stable_frames+1'b1;
                if(track_stable_frames>=2)
                    track_latched<=1'b1;
            end else if(track_latched && track_missed_frames<1) begin
                track_missed_frames<=track_missed_frames+1'b1;
            end else begin
                track_stable_frames<=0;
                track_latched<=1'b0;
                track_missed_frames<=0;
            end
        end
    end
    wire startup_done,fault_safe,servo_limit;
    // PAN_SIGN/TILT_SIGN keep the calibrated direction of the mechanics.
    // 1000..2000 us is the MG90S' own usable range (about 180 deg); the previous
    // 1400..1600 window was a temporary clamp and is what stopped the gimbal
    // after roughly +-30 deg.  If the mechanism hits a hard stop, narrow this
    // again; the status panel shows LIMIT whenever the clamp is active.
    servo_control #(.CLK_HZ(PIXEL_HZ),.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),
                    .PAN_SIGN(-1),.TILT_SIGN(1),
                    .MIN_US(1000),.MAX_US(2000),
                    .SELFTEST_HOLD_MS(SERVO_SELFTEST_HOLD_MS)) servos(
        .clk(I_clk),.rst_n(reset_n),.armed(armed),.follow_enable(follow_enable),.frame_tick(frame_done),.source_alive(source_alive),
        .target_valid(follow_enable),.cx(track_cx_latched),.cy(track_cy_latched),
        .pan_pwm(O_pan_pwm),.tilt_pwm(O_tilt_pwm),
        .moving(moving),.pan_us(pan_us),.tilt_us(tilt_us),
        .startup_done(startup_done),.fault_safe(fault_safe),.limit(servo_limit));
    buzzer_one_shot #(.CLK_HZ(PIXEL_HZ),.TONE_HZ(2000),.DURATION_MS(100)) red_circle_buzzer(
        .clk(I_clk),.rst_n(reset_n),.trigger(stable_target),.buzzer(O_buzzer));
    wire text_hit;
    // Declare pixel coordinates before any OSD or overlay logic uses them.
    reg [11:0] x_stage,y_stage;
    // The status panel reports exactly the object that is being tracked:
    // stage B's compact centre (POSX/POSY), its area and its shape class.
    reg status_valid;
    reg [1:0] status_color,status_shape;
    reg [11:0] status_cx,status_cy;
    reg [15:0] status_area;
    always @* begin
        status_valid = source_alive && tgt_valid;
        status_color = sel_blue ? 2'd2 : 2'd0;
        status_shape = tgt_shape;
        status_cx    = tgt_cx;
        status_cy    = tgt_cy;
        status_area  = tgt_area;
    end
    tracker_osd osd(.clk(I_clk),.rst_n(reset_n),.frame_tick(frame_done),
        .x(x),.y(pixel_y),.cx(status_cx),.cy(status_cy),.mode(mode),.color(status_color),.shape(status_shape),
        .valid(status_valid),.armed(armed),.alive(source_alive),.moving(moving),.overrun(overrun),
        .area(status_area),
        .analysis_cycles(cycles),.latency_us(latency_us),.tag_valid(tag_valid),
        .red_valid(red_valid),.green_valid(green_valid),.blue_valid(blue_valid),
        .red_cx(red_cx),.red_cy(red_cy),.green_cx(green_cx),.green_cy(green_cy),
        .blue_cx(blue_cx),.blue_cy(blue_cy),
        .yellow_valid(yellow_valid),.yellow_cx(yellow_cx),.yellow_cy(yellow_cy),
        .red_area(red_area),.green_area(green_area),.blue_area(blue_area),
        .yellow_area(yellow_area),
        .red_shape(red_shape),.green_shape(green_shape),.blue_shape(blue_shape),.yellow_shape(yellow_shape),
        .red_confidence(red_confidence),.green_confidence(green_confidence),
        .blue_confidence(blue_confidence),.yellow_confidence(yellow_confidence),
        .follow_enable(follow_enable),.limit(servo_limit),
        .red_hits(red_hits),.blue_hits(blue_hits),
        .text_hit(text_hit));
    // Restore the actual Anlogic chip icon. The original 160x160 ROM is kept
    // excluded because its 25-bit sparse case table exceeds this device's
    // LUT budget. The compact decoder preserves its opaque pixels and colors.
    wire logo_region=(IMG_WIDTH>=160 && IMG_HEIGHT>=160 &&
                      x<160 && pixel_y<160);
    wire logo_pixel_hit;
    wire logo_hit;
    wire [23:0] logo_pixel;
    anlogic_logo_compact u_anlogic_logo_compact(
        .clk(I_clk), .rst_n(reset_n),
        .x(x[7:0]), .y(pixel_y[7:0]),
        .hit(logo_pixel_hit), .pixel(logo_pixel));
    assign logo_hit=logo_region && logo_pixel_hit;
    wire tag_region=1'b0;
    // Only the selected target is masked.  The box is stage A's ROI published
    // for the next frame (one frame of mask latency, unchanged) and the colour
    // test is the single measured model, so the object is painted completely
    // while unrelated regions and background pixels of the same box are not.
    wire target_mask_hit;
    // A published-but-empty ROI (no stage A candidate) collapses to a zero box;
    // require a non-degenerate box so a held detection cannot paint pixel (0,0).
    wire tgt_mask_en = tgt_valid && (tgt_mask_r > tgt_mask_l) && (tgt_mask_b > tgt_mask_t);
    tracker_target_mask_gate target_mask_gate(
        .source_alive(source_alive),.target_valid(tgt_mask_en),
        .color_hit(tgt_loose_hit),
        .x(x),.y(pixel_y),
        .left(tgt_mask_l),.right(tgt_mask_r),.top(tgt_mask_t),.bottom(tgt_mask_b),
        .mask_hit(target_mask_hit));
    // Bounding-box edges are intentionally not rendered; only classified
    // target pixels pass through the sparse instance masks above.
    wire box_hit=1'b0;
    wire motion_hit=mvalid && !moving && x>=ml && x<=mr && pixel_y>=mt && pixel_y<=mb &&
                    (x-ml<2 || mr-x<2 || pixel_y-mt<2 || mb-pixel_y<2);
    wire [11:0] cross_x=CENTER_X;
    wire [11:0] cross_y=CENTER_Y;
    wire cross_hit=(x>=cross_x-12 && x<=cross_x+12 && pixel_y==cross_y) ||
                   (pixel_y>=cross_y-12 && pixel_y<=cross_y+12 && x==cross_x);
    wire [9:0] lum={2'b0,rgb_display[23:16]}+{1'b0,rgb_display[15:8],1'b0}+{2'b0,rgb_display[7:0]};
    localparam integer PANEL_X=IMG_WIDTH*7/10;
    function [7:0] contrast;
        input [7:0] c;
        reg [9:0] v;
        begin
            v={2'b0,c}+{3'b0,c[7:1]};
            if(v<64) contrast=0; else if(v>319) contrast=255; else contrast=v-64;
        end
    endfunction
    reg [23:0] processed;
    always @* begin
        case(mode)
            1:processed={3{lum[9:2]}};
            2:processed={contrast(rgb_display[23:16]),contrast(rgb_display[15:8]),contrast(rgb_display[7:0])};
            3:processed=hit ? 24'hffffff : 24'h000000;
            4:processed={3{lum[9:2]}};
            default:processed=rgb_display;
        endcase
    end
    wire [1:0] display_mode_sel;
    wire [23:0] display_rgb;
    wire [23:0] display_source=(display_mode_sel==2'd0) ? processed : rgb_display;
    // Adaptive binary threshold: the frame-mean luminance, latched at the frame
    // boundary.
    //
    // 2026-11-03 (rev F, flicker fix): the mean used to be accumulated from
    // `lum = R + 2G + B`, which spans 0..1020, while only 8 bits of the quotient
    // were kept.  A bright frame therefore wrapped modulo 256 (mean 800 -> 32),
    // so the binary view flipped between "nearly all white" and "nearly all
    // black" from frame to frame - exactly the flicker that was reported.
    // The accumulator now uses the same 77/150/29 luma as display_mode, so the
    // quotient is 0..255 and the units match the comparator exactly.
    localparam integer FRAME_PIXELS = IMG_WIDTH*IMG_HEIGHT;
    localparam integer MEAN_RCP = (32'd4294967295 / FRAME_PIXELS) + 1;
    reg [31:0] lum_sum;
    reg [7:0]  bin_threshold;
    wire [15:0] lum_w = (rgb_display[23:16] * 8'd77) +
                        (rgb_display[15:8]  * 8'd150) +
                        (rgb_display[7:0]   * 8'd29);
    wire [7:0]  lum8 = lum_w[15:8];
    wire [47:0] mean_prod = lum_sum * MEAN_RCP;
    wire [7:0]  lum_mean = mean_prod[39:32];
    // Slight bias above the mean so that symmetric sensor noise mostly lands on
    // the black side instead of sparkling, plus a 1/4 IIR for frame stability.
    // The target is clamped to 240 so the IIR sum can never overflow 8 bits.
    wire [8:0]  mean_raw = {1'b0, lum_mean} + {5'b0, lum_mean[7:4]};
    wire [8:0]  mean_target = (mean_raw > 9'd240) ? 9'd240 : mean_raw;
    wire [10:0] iir_sum = ({2'b0, bin_threshold} * 11'd3) + {2'b0, mean_target};
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            lum_sum<=32'd0;
            bin_threshold<=8'd96;
        end else if(frame_tick) begin
            if (lum_mean < 8'd40)
                bin_threshold <= 8'd40;
            else
                bin_threshold <= iir_sum[9:2];
            lum_sum<=32'd0;
        end else if(de_d[1]) begin
            lum_sum<=lum_sum + {24'd0,lum8};
        end
    end
    display_mode u_display_mode(
        .clk(I_clk),.rst_n(reset_n),.frame_tick(frame_tick),
        .sw1(I_sw1),.sw2(I_sw2),.threshold(bin_threshold),.rgb_in(display_source),
        .mode(display_mode_sel),.rgb_out(display_rgb));
    // Diagnostic bars use the same RGB888 byte convention as the live path:
    // [23:16]=R, [15:8]=G, [7:0]=B.  They isolate HDMI/PHY channel mapping
    // from the camera ISP when DEBUG_MODE is enabled for a board build.
    function [23:0] debug_color_at;
        input [11:0] px;
        input integer width;
        begin
            if(px < width/8)       debug_color_at=24'hff0000;
            else if(px < width*2/8) debug_color_at=24'h00ff00;
            else if(px < width*3/8) debug_color_at=24'h0000ff;
            else if(px < width*4/8) debug_color_at=24'hffff00;
            else if(px < width*5/8) debug_color_at=24'h00ffff;
            else if(px < width*6/8) debug_color_at=24'hff00ff;
            else if(px < width*7/8) debug_color_at=24'hffffff;
            else                        debug_color_at=24'h202020;
        end
    endfunction
    reg [23:0] pix_stage,overlay_stage;
    reg overlay_hit,de_stage,vs_stage,hs_stage;
    // 2026-11-02: the logo decoder is now a 2-cycle block (address register +
    // compare-chain register), so the overlay path uses four stages:
    //   s1: register text/mask/cross/motion hits + pix/DE/HS/VS/coords
    //   s2: register them again (logo output for the same pixel arrives here)
    //   s3: priority mux, all inputs are registers now
    //   s4: output mux + HDMI timing
    // Every pixel-bearing signal is delayed by the same four stages, so the
    // overlay stays aligned with the video pixels.
    reg hit_text_r,hit_mask_r,hit_cross_r,hit_motion_r;
    reg [23:0] pix_r;
    reg de_r,vs_r,hs_r;
    reg [11:0] x_r,y_r;
    reg hit_text_s,hit_mask_s,hit_cross_s,hit_motion_s;
    reg [23:0] pix_s;
    reg de_s,vs_s,hs_s;
    reg [11:0] x_s,y_s;
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            hit_text_r<=0; hit_mask_r<=0;
            hit_cross_r<=0; hit_motion_r<=0;
            pix_r<=0; de_r<=0; vs_r<=0; hs_r<=0; x_r<=0; y_r<=0;
        end else begin
            hit_text_r<=text_hit;
            hit_mask_r<=target_mask_hit;
            hit_cross_r<=cross_hit; hit_motion_r<=(mode==4) && motion_hit;
            pix_r<=display_rgb; de_r<=de_d[1]; vs_r<=vs_d[1]; hs_r<=hs_d[1];
            x_r<=x; y_r<=pixel_y;
        end
    end
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            hit_text_s<=0; hit_mask_s<=0;
            hit_cross_s<=0; hit_motion_s<=0;
            pix_s<=0; de_s<=0; vs_s<=0; hs_s<=0; x_s<=0; y_s<=0;
        end else begin
            hit_text_s<=hit_text_r; hit_mask_s<=hit_mask_r;
            hit_cross_s<=hit_cross_r;
            hit_motion_s<=hit_motion_r;
            pix_s<=pix_r; de_s<=de_r; vs_s<=vs_r; hs_s<=hs_r;
            x_s<=x_r; y_s<=y_r;
        end
    end
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            pix_stage<=0; overlay_stage<=0; overlay_hit<=0;
            x_stage<=0; y_stage<=0;
            de_stage<=0; vs_stage<=0; hs_stage<=0;
        end else begin
            pix_stage<=pix_s; de_stage<=de_s; vs_stage<=vs_s; hs_stage<=hs_s;
            x_stage<=x_s; y_stage<=y_s;
            overlay_hit<=hit_text_s || logo_hit || hit_mask_s ||
                         hit_cross_s || hit_motion_s;
            if(hit_cross_s) overlay_stage<=24'hffffff;
            else if(hit_text_s) overlay_stage<=24'hfff080;
            else if(logo_hit) overlay_stage<=logo_pixel[23:0];
            else if(tag_region) overlay_stage<=24'd0;
            else if(hit_mask_s) overlay_stage<=sel_blue ? 24'h40b0ff : 24'hff3030;
            else overlay_stage<=24'hff8040;
        end
    end
    always @(posedge I_clk or negedge reset_n) begin
        if(!reset_n) begin
            O_hdmi_data<=0; O_hdmi_de<=0; O_hdmi_vsync<=0; O_hdmi_hsync<=0;
        end else begin
            O_hdmi_de<=de_stage; O_hdmi_vsync<=vs_stage; O_hdmi_hsync<=hs_stage;
            if(!de_stage)
                O_hdmi_data<=24'd0;
            else if(DEBUG_MODE == 1)
                O_hdmi_data<=debug_color_at(x_stage,IMG_WIDTH);
            // Independent of camera/DDR, display mode and recognition input.
            // Keep a small known-color reference below the sidebar logo.
    else if(COLOR_REFERENCE && x_stage>=PANEL_X && x_stage<IMG_WIDTH && y_stage<24)
                O_hdmi_data<=debug_color_at(x_stage-(IMG_WIDTH-(IMG_WIDTH-PANEL_X)),IMG_WIDTH-PANEL_X);
            else
                O_hdmi_data<=overlay_hit ? overlay_stage : pix_stage;
        end
    end
endmodule
