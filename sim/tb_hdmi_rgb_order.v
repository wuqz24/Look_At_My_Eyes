`timescale 1ns/1ps

// Exercise the production mixer, not a stand-in assign statement.
// The encrypted HDMI encoder and physical pins still require board testing.
module tb_hdmi_rgb_order;
    reg clk=0,rst_n=0,de=0,vs=0;
    always #5 clk=~clk;
    wire [23:0] bars,normal;
    reg [23:0] source=0,data0=0,data1=0;
    wire bars_de,normal_de;
    integer x,y,ox=0,oy=0,count=0;
    reg checking=0;
    function [23:0] color_at;
        input integer index;
        begin
            case(index)
                0:color_at=24'hff0000;
                1:color_at=24'h00ff00;
                2:color_at=24'h0000ff;
                3:color_at=24'hffff00;
                4:color_at=24'h00ffff;
                5:color_at=24'hff00ff;
                6:color_at=24'hffffff;
                default:color_at=24'h202020;
            endcase
        end
    endfunction
    function [23:0] live_pixel;
        input integer px;
        begin
            case(px%4)
                0:live_pixel=24'h0000ff;
                1:live_pixel=24'hffff00;
                2:live_pixel=24'h123456;
                default:live_pixel=24'hc08020;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        data0<=source;
        data1<=data0;
    end
    hdmi_mixer #(.DEBUG_MODE(1)) diagnostic(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_de(de),.I_video_vsync(vs),.I_video_hsync(1'b0),
        .I_video_user(1'b0),.I_video_last(1'b0),.I_debug_status(4'd0),
        .I_mode_n(1'b1),.I_color_n(1'b1),.I_arm_n(1'b1),.I_capture_toggle(1'b0),
        .I_sw1(1'b0),.I_sw2(1'b0),.I_video_rd_data(data1),
        .O_hdmi_de(bars_de),.O_hdmi_data(bars));
    hdmi_mixer #(.DEBUG_MODE(0)) live_view(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_de(de),.I_video_vsync(vs),.I_video_hsync(1'b0),
        .I_video_user(1'b0),.I_video_last(1'b0),.I_debug_status(4'd0),
        .I_mode_n(1'b1),.I_color_n(1'b1),.I_arm_n(1'b1),.I_capture_toggle(1'b0),
        .I_sw1(1'b0),.I_sw2(1'b0),.I_video_rd_data(data1),
        .O_hdmi_de(normal_de),.O_hdmi_data(normal));
    always @(posedge clk) begin
        #1;
        if(checking) begin
            if(bars_de!==normal_de) $fatal(1,"diagnostic changed DE timing");
            if(bars_de) begin
                if(bars!==color_at(ox/160))
                    $fatal(1,"production color bar mismatch x=%0d got=%h expected=%h",ox,bars,color_at(ox/160));
                if(oy==196 && ox<896 && normal!==live_pixel(ox))
                    $fatal(1,"normal RGB byte order changed x=%0d rgb=%h",ox,normal);
                if(oy>=184 && oy<208 && ox>=896 && normal!==color_at((ox-896)/48))
                    $fatal(1,"live reference strip mismatch x=%0d y=%0d rgb=%h",ox,oy,normal);
                count=count+1;
                if(ox==1279) begin ox=0; oy=oy+1; end else ox=ox+1;
            end else if(bars!==0 || normal!==0) $fatal(1,"blanking is not black");
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        repeat(12) @(negedge clk); vs=1;
        repeat(4) @(negedge clk); vs=0;
        repeat(8) @(negedge clk); checking=1;
        for(y=0;y<208;y=y+1) begin
            for(x=0;x<1280;x=x+1) begin
                @(negedge clk); de=1; source=live_pixel(x);
            end
            @(negedge clk); de=0;
            repeat(8) @(negedge clk);
        end
        repeat(10) @(negedge clk);
        if(count!=266240) $fatal(1,"diagnostic pixel count %0d",count);
        $display("PASS hdmi_rgb_order: production mixer bars, live reference strip, RGB bytes and blanking");
        $finish;
    end
    initial begin #4000000; $fatal(1,"RGB diagnostic timeout"); end
endmodule
