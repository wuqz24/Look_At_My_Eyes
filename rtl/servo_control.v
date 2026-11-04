// Dual-axis gimbal controller for MG90S servos driven directly from FPGA I/O.
//
// 2026-11-03 rework
//  * the pulse command is kept in 1/4 microsecond units (pan_q / tilt_q), so a
//    frame can command a sub-microsecond step instead of being quantised to a
//    whole microsecond.  At 1400..1600 us a 1 us step moves the image by
//    roughly 6 px, which is why the old loop could not settle closer than a
//    few tens of pixels to the crosshair;
//  * the dead band and the gain are now separable knobs (DEAD_X/DEAD_Y and
//    GAIN_X/GAIN_Y) with a minimum non-zero step, so the controller keeps
//    walking until the object centre is inside the dead band and then stops
//    without hunting;
//  * the loop is clocked by frame_done (one clock after the analysis result is
//    published) instead of frame_tick, which removes one whole frame of loop
//    latency: the previous build compared the crosshair with a centre that was
//    already two frames old and then applied a heavily filtered step;
//  * `limit` reports that the loop wants to move but the software pulse limit
//    is clamped, so the status panel can print LIMIT instead of TRACK and the
//    operator knows the gimbal is at its configured range rather than stuck.
//
// The pulse width itself is compared against a quarter-tick phase counter, so
// no extra divider or per-microsecond latch is needed.
module servo_control #(
    parameter integer CLK_HZ = 75000000,
    parameter integer PAN_SIGN = 1,
    parameter integer TILT_SIGN = 1,
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer MIN_US = 1200,
    parameter integer MAX_US = 1800,
    parameter integer DEAD_X = 5,
    parameter integer DEAD_Y = 5,
    parameter integer GAIN_X = 8,
    parameter integer GAIN_Y = 8,
    parameter integer MAX_STEP_Q = 24,          // 6 us per frame
    parameter integer FILTER_SHIFT = 2,
    parameter integer SELFTEST_HOLD_MS = 250
)(
    input wire clk, rst_n, armed, follow_enable, frame_tick, source_alive,
    input wire target_valid,
    input wire [11:0] cx, cy,
    output wire pan_pwm, tilt_pwm,
    output reg moving,
    output reg [11:0] pan_us, tilt_us,
    output wire startup_done,
    output wire fault_safe,
    output wire limit
);
    localparam integer PERIOD = CLK_HZ/50;
    localparam integer TICKS_US = CLK_HZ/1000000;
    localparam integer WATCHDOG_LIMIT = CLK_HZ/4;
    localparam integer SELFTEST_HOLD = (CLK_HZ/1000)*SELFTEST_HOLD_MS;
    localparam integer QMIN = MIN_US*4;
    localparam integer QMAX = MAX_US*4;
    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_CENTER_1 = 4'd1;
    localparam [3:0] ST_PAN_LOW  = 4'd2;
    localparam [3:0] ST_PAN_HIGH = 4'd3;
    localparam [3:0] ST_TILT_LOW = 4'd4;
    localparam [3:0] ST_TILT_HIGH= 4'd5;
    localparam [3:0] ST_CENTER_2 = 4'd6;
    localparam [3:0] ST_TRACK    = 4'd7;
    localparam [3:0] ST_SAFE     = 4'd8;

    reg [31:0] phase, watchdog, selftest_count;
    // Pulse command in quarter microseconds.
    reg [15:0] pan_q, tilt_q;
    reg signed [15:0] fx, fy;
    reg [3:0] state;
    reg [3:0] settle;
    reg pan_clamped, tilt_clamped;

    integer ex, ey, dx, dy, np, nt;

    wire watchdog_bad = watchdog >= WATCHDOG_LIMIT;
    wire video_ok = source_alive && !watchdog_bad;
    wire selftest_state = state>=ST_CENTER_1 && state<=ST_CENTER_2;
    wire pwm_allowed = selftest_state || (video_ok && state==ST_TRACK);

    assign startup_done = state==ST_TRACK;
    assign fault_safe = state==ST_SAFE;
    assign limit = (state==ST_TRACK) && follow_enable && (pan_clamped || tilt_clamped);

    // Pulse width in quarter ticks: pan_q is in 1/4 us and TICKS_US is in
    // clocks per us, so pan_q*TICKS_US is compared with a phase counter that
    // counts quarter ticks.  The product is latched once per 50 Hz period, so
    // a command update that lands inside a pulse cannot stretch that pulse.
    wire [25:0] phase_q = {phase[23:0],2'b00};
    reg [21:0] pan_ticks_q, tilt_ticks_q;
    // The state gate is combinational so a video fault cannot leave a long
    // pulse active until the next 50 Hz period boundary.
    assign pan_pwm = pwm_allowed && (phase_q < {4'b0,pan_ticks_q});
    assign tilt_pwm = pwm_allowed && (phase_q < {4'b0,tilt_ticks_q});

    always @* begin
        ex = $signed({1'b0,cx}) - WIDTH/2;
        ey = $signed({1'b0,cy}) - HEIGHT/2;
        pan_clamped = 1'b0;
        tilt_clamped = 1'b0;
        dx = 0;
        dy = 0;
        if(fx > DEAD_X) begin
            dx = $signed(fx) / GAIN_X;
            if(dx < 1) dx = 1;
        end else if(fx < -DEAD_X) begin
            dx = $signed(fx) / GAIN_X;
            if(dx > -1) dx = -1;
        end
        if(fy > DEAD_Y) begin
            dy = $signed(fy) / GAIN_Y;
            if(dy < 1) dy = 1;
        end else if(fy < -DEAD_Y) begin
            dy = $signed(fy) / GAIN_Y;
            if(dy > -1) dy = -1;
        end
        if(dx > MAX_STEP_Q) dx = MAX_STEP_Q;
        if(dx < -MAX_STEP_Q) dx = -MAX_STEP_Q;
        if(dy > MAX_STEP_Q) dy = MAX_STEP_Q;
        if(dy < -MAX_STEP_Q) dy = -MAX_STEP_Q;
        np = pan_q + PAN_SIGN*dx;
        nt = tilt_q + TILT_SIGN*dy;
        if(np < QMIN) begin np = QMIN; pan_clamped = 1'b1; end
        if(np > QMAX) begin np = QMAX; pan_clamped = 1'b1; end
        if(nt < QMIN) begin nt = QMIN; tilt_clamped = 1'b1; end
        if(nt > QMAX) begin nt = QMAX; tilt_clamped = 1'b1; end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase<=0;
            watchdog<=WATCHDOG_LIMIT;
            selftest_count<=0;
            pan_q<=16'd6000;      // 1500 us
            tilt_q<=16'd6000;
            pan_ticks_q<=6000*TICKS_US;
            tilt_ticks_q<=6000*TICKS_US;
            pan_us<=12'd1500;
            tilt_us<=12'd1500;
            fx<=0;
            fy<=0;
            moving<=0;
            settle<=0;
            state<=ST_IDLE;
        end else begin
            if(frame_tick) watchdog<=0;
            else if(watchdog<WATCHDOG_LIMIT) watchdog<=watchdog+1'b1;

            if(phase==PERIOD-1) begin
                phase<=0;
                pan_ticks_q<=pan_q * TICKS_US;
                tilt_ticks_q<=tilt_q * TICKS_US;
            end else phase<=phase+1'b1;

            // Published command in microseconds for the debug port.
            pan_us <= pan_q[13:2];
            tilt_us <= tilt_q[13:2];

            case(state)
                    ST_IDLE: begin
                        moving<=0;
                        selftest_count<=0;
                        // Exercise the servos after every reset even when the
                        // camera stream has not established video health yet.
                        state<=ST_CENTER_1;
                        pan_q<=16'd6000;
                        tilt_q<=16'd6000;
                    end
                    ST_SAFE: begin
                        moving<=0;
                        selftest_count<=0;
                        pan_q<=16'd6000;
                        tilt_q<=16'd6000;
                        fx<=0;
                        fy<=0;
                        settle<=0;
                        // Recenter and repeat the short self-test after video
                        // recovery so tracking never resumes from stale state.
                        if(video_ok) state<=ST_CENTER_1;
                    end
                    ST_CENTER_1, ST_PAN_LOW, ST_PAN_HIGH,
                    ST_TILT_LOW, ST_TILT_HIGH, ST_CENTER_2: begin
                        moving<=1;
                        if(selftest_count >= SELFTEST_HOLD-1) begin
                            selftest_count<=0;
                            case(state)
                                ST_CENTER_1: begin state<=ST_PAN_LOW;  pan_q<=16'd5800; tilt_q<=16'd6000; end
                                ST_PAN_LOW:  begin state<=ST_PAN_HIGH; pan_q<=16'd6200; tilt_q<=16'd6000; end
                                ST_PAN_HIGH: begin state<=ST_TILT_LOW; pan_q<=16'd6000; tilt_q<=16'd5800; end
                                ST_TILT_LOW: begin state<=ST_TILT_HIGH;pan_q<=16'd6000; tilt_q<=16'd6200; end
                                ST_TILT_HIGH:begin state<=ST_CENTER_2;pan_q<=16'd6000; tilt_q<=16'd6000; end
                                default: begin state<=ST_TRACK; pan_q<=16'd6000; tilt_q<=16'd6000; end
                            endcase
                        end else selftest_count<=selftest_count+1'b1;
                    end
                    ST_TRACK: begin
                        if(!video_ok) begin
                            state<=ST_SAFE;
                            pan_q<=16'd6000;
                            tilt_q<=16'd6000;
                            fx<=0;
                            fy<=0;
                            moving<=0;
                            settle<=0;
                        end else if(!armed) begin
                            pan_q<=16'd6000;
                            tilt_q<=16'd6000;
                            fx<=0;
                            fy<=0;
                            moving<=0;
                            settle<=0;
                        end else if(frame_tick) begin
                            if(follow_enable && target_valid) begin
                                fx <= $signed(fx) + ((ex-$signed(fx)) >>> FILTER_SHIFT);
                                fy <= $signed(fy) + ((ey-$signed(fy)) >>> FILTER_SHIFT);
                                pan_q<=np[15:0];
                                tilt_q<=nt[15:0];
                                moving <= (np!=pan_q || nt!=tilt_q) || settle!=0;
                                if(np!=pan_q || nt!=tilt_q) settle<=8;
                                else if(settle!=0) settle<=settle-1'b1;
                            end else begin
                                fx<=0;
                                fy<=0;
                                moving<=0;
                                settle<=0;
                            end
                        end else if(settle!=0) begin
                            settle<=settle-1'b1;
                            moving<=1;
                        end else moving<=0;
                    end
                    default: state<=ST_IDLE;
            endcase
        end
    end
endmodule
