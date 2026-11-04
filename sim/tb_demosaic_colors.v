`timescale 1ns/1ps
// Catch wrong Bayer phase, RAW lane reversal and RGB byte permutation.
// Interior pixels of a constant-color Bayer plane must reconstruct that color.
module tb_demosaic_colors;
    localparam W = 64, H = 8;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [39:0] raw_data = 0;
    reg valid = 0, user = 0, last = 0;
    wire [127:0] rgb;
    wire out_valid, out_user, out_last;
    reg [23:0] color;
    integer x, y, lane, received = 0, checked = 0, ox, oy;

    demosaic #(.IMG_WIDTH(W), .IMG_HEIGHT(H),
               .data_complete_delay(8), .BAYER_MODE("BGGR")) dut (
        .I_clk(clk), .I_rst_n(rst_n), .axi4s_video_tdata(raw_data),
        .axi4s_video_tdest(10'd0), .axi4s_video_tvalid(valid),
        .axi4s_video_tuser(user), .axi4s_video_tlast(last),
        .axi4s_video_tready(), .O_tdata(rgb), .O_tvalid(out_valid),
        .O_tuser(out_user), .O_tlast(out_last), .O_tready(1'b1)
    );

    function [9:0] sample;
        input integer row, col;
        input [23:0] c;
        begin
            if (!(row % 2))
                sample = (!(col % 2) ? c[7:0] : c[15:8]) * 4;
            else
                sample = (!(col % 2) ? c[15:8] : c[23:16]) * 4;
        end
    endfunction

    always @(negedge clk) if (rst_n && out_valid) begin
        ox = (received % (W/4))*4;
        oy = received / (W/4);
        if (out_user !== (received == 0) || out_last !== (ox == W-4))
            $fatal(1, "demosaic framing beat=%0d user=%b last=%b", received, out_user, out_last);
        if (oy >= 2 && ox >= 8 && ox < W-8) begin
            for (lane = 0; lane < 4; lane = lane+1) begin
                if (rgb[lane*32 +: 24] !== color)
                    $fatal(1, "Bayer/RGB mismatch row=%0d x=%0d lane=%0d got=%h expected=%h",
                           oy, ox, lane, rgb[lane*32 +: 24], color);
                checked = checked + 1;
            end
        end
        received = received+1;
    end

    task frame;
        input [23:0] c;
        begin
            @(posedge clk); #1;
            rst_n = 0;
            repeat (4) @(posedge clk);
            #1;
            received = 0; checked = 0; color = c; rst_n = 1;
            for (y = 0; y < H; y = y+1) begin
                for (x = 0; x < W; x = x+4) begin
                    @(posedge clk); #1;
                    valid = 1; user = (y == 0 && x == 0); last = (x == W-4);
                    raw_data = {sample(y,x+3,c), sample(y,x+2,c), sample(y,x+1,c), sample(y,x,c)};
                end
                @(posedge clk); #1; valid = 0; user = 0; last = 0;
                repeat (40) @(posedge clk);
            end
            repeat (80) @(posedge clk);
            #1;
            if (received != W*H/4 || checked != (H-2)*(W-16))
                $fatal(1, "demosaic incomplete frame received=%0d checked=%0d", received, checked);
        end
    endtask

    initial begin
        frame(24'hc00000); frame(24'h00c000); frame(24'h0000c0);
        frame(24'hc0c000); frame(24'h808080); frame(24'h2060a0);
        $display("PASS demosaic_colors: BGGR interior colors and full-frame beat/sideband counts");
        $finish;
    end
    initial begin #1000000; $fatal(1, "timeout"); end
endmodule
