`timescale 1ns/1ps
module tb_control;
    reg clk=0,rst_n=0,mn=1,cn=1,an=1,ft=0;
    always #5 clk=~clk;
    wire [2:0] mode;
    wire [1:0] color;
    wire armed;
    integer i;
    tracker_control #(.DEBOUNCE_CYCLES(8)) dut(.clk(clk),.rst_n(rst_n),
        .mode_n(mn),.color_n(cn),.arm_n(an),.frame_tick(ft),.mode(mode),.color(color),.armed(armed));
    task tick;
        begin @(negedge clk); ft=1; @(negedge clk); ft=0; end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        repeat(4) @(negedge clk);
        if(armed || mode || color) $fatal(1,"defaults");
        mn=0; repeat(3) @(negedge clk); mn=1; repeat(12) @(negedge clk); tick;
        if(mode) $fatal(1,"bounce");
        mn=0; cn=0; repeat(16) @(negedge clk);
        if(mode || color) $fatal(1,"midframe changed");
        tick; if(mode!=1 || color!=1) $fatal(1,"switch");
        repeat(40) @(negedge clk); tick;
        if(mode!=1 || color!=1) $fatal(1,"hold repeats");
        for(i=0;i<4;i=i+1) begin
            mn=1; cn=1; repeat(16) @(negedge clk);
            mn=0; cn=0; repeat(16) @(negedge clk); tick;
        end
        if(mode!=0 || color!=2) $fatal(1,"wrap");
        an=0; repeat(4) @(negedge clk); if(!armed) $fatal(1,"arm");
        an=1; repeat(4) @(negedge clk); if(armed) $fatal(1,"disarm");
        $display("PASS control: debounce, hold, frame-boundary apply, wrap, default disarm");
        $finish;
    end
endmodule
