`timescale 1ns/1ps
module tb_mixer;
    reg clk=0,rst_n=0,de=0,vs=0,hs=0;
    always #5 clk=~clk;
    reg [23:0] data0=0,data1=0,source=0;
    reg sw1=0,sw2=0;
    wire ode,ovs,ohs,rd;
    wire [23:0] out;
    reg [3:0] deq=0,vsq=0,hsq=0;
    integer xx,yy,count=0,ox=0,oy=0;
    reg checking=0;
    hdmi_mixer #(.IMG_WIDTH(256),.IMG_HEIGHT(256)) dut(.I_clk(clk),.I_rst_n(rst_n),
        .I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(1'b0),.I_video_last(1'b0),
        .I_debug_status(4'd0),.I_mode_n(1'b1),.I_color_n(1'b1),.I_arm_n(1'b1),.I_capture_toggle(1'b0),
        .I_sw1(sw1),.I_sw2(sw2),
        .O_video_rd_en(rd),.I_video_rd_data(data1),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(out));
    always @(posedge clk) begin
        data0<=source; data1<=data0;
        deq<={deq[2:0],de}; vsq<={vsq[2:0],vs}; hsq<={hsq[2:0],hs};
        #1;
        if(checking) begin
            if(ode!==deq[3] || ovs!==vsq[3] || ohs!==hsq[3]) $fatal(1,"sync alignment");
            if(ode) begin
                count=count+1;
                if(ox==128 && oy==128 && out!==24'hffffff) $fatal(1,"center cross misaligned x=%d y=%d rgb=%h",ox,oy,out);
                if(oy>=208 && out!=={(8'h80 | oy[1:0]),(8'h80 | ox[1:0]),8'h80}) $fatal(1,"pixel alignment x=%d y=%d rgb=%h",ox,oy,out);
                if(ox==255) begin ox=0; oy=oy+1; end else ox=ox+1;
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1; repeat(12) @(negedge clk);
        checking=1; vs=1; repeat(3) @(negedge clk); vs=0; repeat(8) @(negedge clk);
        for(yy=0;yy<256;yy=yy+1) begin
            for(xx=0;xx<256;xx=xx+1) begin
                @(negedge clk); de=1; source={(8'h80 | yy[1:0]),(8'h80 | xx[1:0]),8'h80};
            end
            @(negedge clk); de=0; hs=1;
            repeat(4) @(negedge clk); hs=0; repeat(4) @(negedge clk);
        end
        repeat(12) @(negedge clk);
        if(count!=65536 || oy!=256) $fatal(1,"pixel count");
        $display("PASS mixer: 2-cycle mock DDR read, 4-cycle sync alignment, line edges and pixel count");
        $finish;
    end
endmodule
