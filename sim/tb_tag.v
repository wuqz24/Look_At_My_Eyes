`timescale 1ns/1ps
module tb_tag;
    reg clk=0,rst_n=0,cs=0,fs=0,v=0,de=0;
    always #5 clk=~clk;
    reg [11:0] x=0,y=2;
    reg [23:0] rgb=0;
    wire [31:0] gray,latency;
    wire [127:0] encoded;
    wire alive,tag_valid;
    reg [127:0] saved;
    integer i;
    frame_tag_tx tx(.clk(clk),.rst_n(rst_n),.capture_start(cs),.frame_start(fs),.valid(v),
        .time_gray(gray),.data_in(128'd0),.data_out(encoded));
    frame_tag_rx #(.CLK_HZ(1000000)) rx(.clk(clk),.rst_n(rst_n),.de(de),.x(x),.y(y),.rgb(rgb),
        .time_gray(gray),.latency_us(latency),.alive(alive),.tag_valid(tag_valid));
    task play;
        begin
            for(i=0;i<6;i=i+1) begin
                @(negedge clk); de=1; x=i;
                case(i)
                    0:rgb=saved[127:104]; 1:rgb=saved[103:80]; 2:rgb=saved[79:56];
                    3:rgb=saved[55:32]; 4:rgb=saved[31:8]; 5:rgb={saved[7:0],16'd0};
                endcase
            end
            @(negedge clk); de=0;
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        repeat(10) @(negedge clk); cs=1; fs=1;
        @(negedge clk); cs=0; fs=0; v=1;
        repeat(480) @(negedge clk);
        #1; saved=encoded;
        if(saved[127:104]!=24'hc35a7e || saved[71:40]!=1) $fatal(1,"tag position/id");
        @(negedge clk); v=0;
        repeat(100) @(negedge clk); play;
        if(!tag_valid || !alive || latency<580 || latency>620) $fatal(1,"tag/latency %d",latency);
        repeat(100001) @(negedge clk); play;
        if(alive) $fatal(1,"replayed frozen frame renewed watchdog");
        saved[40]=~saved[40]; saved[8]=~saved[8]; play;
        if(tag_valid || alive) $fatal(1,"corrupt tag");
        $display("PASS tag: packed-word location, timestamp, replay timeout, corrupt marker rejection");
        $finish;
    end
endmodule
