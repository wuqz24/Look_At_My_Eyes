`timescale 1ns/1ps
module tb_csi_raw10_order;
    reg clk=0, rst_n=0, hs_valid=0;
    reg [15:0] hs_data=0;
    always #5 clk=~clk;
    wire fs,fe,valid,raw_fs,raw_fe,raw_valid;
    wire [31:0] data;
    wire [39:0] raw_data;
    reg [7:0] bytes [0:19];
    integer frame=0,line=0,g,p,i,groups=0,starts=0,ends=0;
    reg [9:0] sample;
    csi_unpacket_2lane csi(
        .I_clk(clk),.I_rst_n(rst_n),.I_hs_valid(hs_valid),.I_hs_data(hs_data),
        .O_csi_frame_start(fs),.O_csi_frame_end(fe),.O_csi_valid(valid),
        .O_csi_data(data),.O_csi_hs());
    raw10_unpacket_2lane raw10(
        .I_clk(clk),.I_rst_n(rst_n),.I_csi_frame_start(fs),.I_csi_frame_end(fe),
        .I_csi_valid(valid),.I_csi_data(data),.I_camera_black_level(10'd0),
        .O_raw10_frame_start(raw_fs),.O_raw10_frame_end(raw_fe),
        .O_raw10_valid(raw_valid),.O_raw10_data(raw_data));
    function [9:0] pixel;
        input integer index;
        begin pixel = (index*67 + frame*31 + line*103) % 1024; end
    endfunction
    task halfword;
        input [15:0] value;
        begin @(negedge clk); hs_valid=1; hs_data=value; end
    endtask
    task gap;
        begin
            @(negedge clk); hs_valid=0; hs_data=0;
            repeat(16) @(negedge clk);
        end
    endtask
    always @(posedge clk) begin
        #1;
        if(rst_n) begin
            if(raw_fs) starts=starts+1;
            if(raw_fe) ends=ends+1;
            if(raw_valid) begin
                for(i=0;i<4;i=i+1)
                    if(raw_data[i*10 +: 10] !== pixel(groups*4+i))
                        $fatal(1,"RAW10 order frame=%0d line=%0d group=%0d pixel=%0d got=%h",
                            frame,line,groups,i,raw_data[i*10 +: 10]);
                groups=groups+1;
            end
        end
    end
    initial begin
        repeat(20) @(negedge clk); rst_n=1;
        for(frame=0;frame<4;frame=frame+1) begin
            halfword(16'h0000); halfword(16'h0000); gap();
            for(line=0;line<4;line=line+1) begin
                groups=0;
                for(g=0;g<4;g=g+1) begin
                    bytes[g*5+4]=0;
                    for(p=0;p<4;p=p+1) begin
                        sample=pixel(g*4+p);
                        bytes[g*5+p]=sample[9:2];
                        bytes[g*5+4][p*2 +: 2]=sample[1:0];
                    end
                end
                halfword(16'h2b14); halfword(16'h0000);
                for(p=0;p<20;p=p+2) halfword({bytes[p],bytes[p+1]});
                halfword(16'h0000); gap();
                if(groups!=4) $fatal(1,"RAW10 line produced %0d groups instead of 4",groups);
            end
            halfword(16'h0100); halfword(16'h0000); gap();
        end
        if(starts!=4 || ends!=4) $fatal(1,"frame markers starts=%0d ends=%0d",starts,ends);
        $display("PASS csi_raw10_order: 4 frames, 16 lines, 256 exact RAW10 pixels, P0 in low bits");
        $finish;
    end
    initial begin #100000; $fatal(1,"CSI test timeout"); end
endmodule
