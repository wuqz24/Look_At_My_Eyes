`timescale 1ns/1ps
module tb_tracker;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,de=0,frame_tick=0,moving=0,alive=1;
    reg [11:0] x=0,y=0;
    reg [23:0] rgb=0;
    reg [1:0] color=0;
    wire hit,valid,mvalid,busy,overrun;
    wire [11:0] l,r,t,b,cx,cy,ml,mr,mt,mb;
    wire [12:0] area;
    wire [1:0] shape;
    wire [31:0] cycles;
    integer xx,yy,scenario,timeout;
    vision_core #(.WIDTH(256),.HEIGHT(256)) dut(
        .clk(clk),.rst_n(rst_n),.de(de),.frame_tick(frame_tick),.x(x),.y(y),.rgb(rgb),
        .color(color),.moving(moving),.source_alive(alive),.color_hit(hit),.target_valid(valid),
        .left(l),.right(r),.top(t),.bottom(b),.cx(cx),.cy(cy),.area(area),.shape(shape),
        .motion_valid(mvalid),.motion_left(ml),.motion_right(mr),.motion_top(mt),.motion_bottom(mb),
        .busy(busy),.overrun(overrun),.analysis_cycles(cycles));
    task send_frame;
        input integer scene;
        begin
            @(negedge clk); frame_tick=1;
            @(negedge clk); frame_tick=0;
            for(yy=0;yy<256;yy=yy+1) begin
                for(xx=0;xx<256;xx=xx+1) begin
                    @(negedge clk); x=xx; y=yy; de=1; rgb=24'h303030;
                    if(scene==1 && ((xx>=32 && xx<160 && yy>=64 && yy<192) || (xx>=192 && yy<64))) rgb=24'hff1010;
                    if(scene==2 && xx<64 && yy<64) rgb=24'hff1010;
                    if(scene==3) rgb=24'hff1010;
                    if(scene==4 && xx>=192 && yy>=192) rgb=24'h1010ff;
                end
                @(negedge clk); de=0;
                repeat(4) @(negedge clk);
            end
            timeout=0;
            while(busy && timeout<20000) begin @(negedge clk); timeout=timeout+1; end
            if(busy || overrun) $fatal(1,"analysis deadline/overrun");
            repeat(8) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        send_frame(0); if(valid || mvalid) $fatal(1,"empty startup");
        send_frame(1); if(valid) $fatal(1,"premature lock");
        send_frame(1);
        if(!valid || l!=32 || r!=159 || t!=64 || b!=191 || area!=16 || cx!=95 || cy!=127)
            $fatal(1,"largest component bbox valid=%d l=%d r=%d t=%d b=%d a=%d",valid,l,r,t,b,area);
        if(mvalid) $fatal(1,"static scene reported moving");
        send_frame(0); if(valid) $fatal(1,"lost target retained");
        send_frame(2); send_frame(2);
        if(!valid || l!=0 || t!=0 || r!=63 || b!=63) $fatal(1,"top left edge");
        send_frame(3); if(valid) $fatal(1,"full background accepted");
        color=2; send_frame(4); send_frame(4); send_frame(4);
        if(!valid || l!=192 || r!=255 || t!=192 || b!=255) $fatal(1,"blue bottom right");
        moving=1; send_frame(0); if(mvalid) $fatal(1,"camera motion not inhibited");
        alive=0; send_frame(4); if(valid) $fatal(1,"source lost");
        $display("PASS vision: largest component, colors, empty, borders, background, loss, motion inhibit");
        $finish;
    end
endmodule
