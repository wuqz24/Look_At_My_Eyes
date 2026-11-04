`timescale 1ns/1ps
module tb_fullframe;
    reg clk=0,rst_n=0,de=0,ft=0;
    always #5 clk=~clk;
    reg [11:0] x=0,y=0;
    reg [23:0] rgb=0;
    wire valid,busy,overrun;
    wire [11:0] l,r,t,b;
    wire [12:0] area;
    wire [31:0] cycles;
    integer xx,yy,waited;
    vision_core dut(.clk(clk),.rst_n(rst_n),.de(de),.frame_tick(ft),.x(x),.y(y),.rgb(rgb),
        .color(2'd0),.moving(1'b0),.source_alive(1'b1),.target_valid(valid),
        .left(l),.right(r),.top(t),.bottom(b),.area(area),.busy(busy),.overrun(overrun),.analysis_cycles(cycles));
    task frame;
        input integer full;
        begin
            @(negedge clk); ft=1;
            @(negedge clk); ft=0;
            for(yy=0;yy<720;yy=yy+1) begin
                for(xx=0;xx<1280;xx=xx+1) begin
                    @(negedge clk); de=1; x=xx; y=yy;
                    rgb=(full!=0 || (xx>=1152 && yy>=640)) ? 24'hff1010 : 24'h202020;
                end
                @(negedge clk); de=0;
                if(yy!=719) repeat(369) @(negedge clk);
            end
            waited=0;
            while(busy && waited<49500) begin @(negedge clk); waited=waited+1; end
            if(busy || overrun || cycles>=49500) $fatal(1,"720p blank deadline");
            $display("720p full=%0d scan_cycles=%0d area=%0d",full,cycles,area);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        frame(0); frame(0);
        if(!valid || l!=1152 || r!=1279 || t!=640 || b!=719 || area!=12)
            $fatal(1,"720p partial final row bbox");
        frame(1);
        if(valid || area!=920) $fatal(1,"920-cell queue/background rejection");
        $display("PASS fullframe: 1280x720, partial row, 920-node BFS, vertical blank deadline");
        $finish;
    end
endmodule
