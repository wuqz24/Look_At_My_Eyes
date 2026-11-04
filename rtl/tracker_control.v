module tracker_control #(
    parameter integer CLK_HZ = 75000000,
    parameter integer DEBOUNCE_CYCLES = 750000,
    parameter integer USE_ARM_INPUT = 1
)(
    input wire clk, rst_n,
    input wire mode_n, color_n, arm_n,
    input wire frame_tick,
    output reg [2:0] mode,
    output reg [1:0] color,
    output wire armed
);
    reg [1:0] ms, cs, ars;
    reg md, cd;
    reg [20:0] mc, cc;
    reg [2:0] pending_mode;
    reg [1:0] pending_color;
    assign armed = USE_ARM_INPUT ? ~ars[1] : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms<=3; cs<=3; ars<=3; md<=1; cd<=1;
            mc<=0; cc<=0; mode<=0; color<=0;
            pending_mode<=0; pending_color<=0;
        end else begin
            ms<={ms[0],mode_n}; cs<={cs[0],color_n}; ars<={ars[0],arm_n};
            if(ms[1]==md) mc<=0;
            else if(mc==DEBOUNCE_CYCLES-1) begin
                mc<=0; md<=ms[1];
                if(!ms[1]) pending_mode <= pending_mode==4 ? 0 : pending_mode+1'b1;
            end else mc<=mc+1'b1;
            if(cs[1]==cd) cc<=0;
            else if(cc==DEBOUNCE_CYCLES-1) begin
                cc<=0; cd<=cs[1];
                // Only red and blue are active target classes.
                if(!cs[1]) pending_color <= pending_color==2 ? 0 : 2;
            end else cc<=cc+1'b1;
            if(frame_tick) begin mode<=pending_mode; color<=pending_color; end
        end
    end
endmodule
