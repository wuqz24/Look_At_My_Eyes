`timescale 1ns/1ps

module tb_awb_enhance;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg        in_valid = 1'b0;
    reg        in_user = 1'b0;
    reg        in_last = 1'b0;
    reg [95:0] in_data = 96'd0;
    wire       in_ready;
    wire       out_valid;
    wire       out_user;
    wire       out_last;
    wire [95:0] out_data;
    reg        out_ready = 1'b1;

    wire       lift_in_ready;
    wire       lift_out_valid;
    wire       lift_out_user;
    wire       lift_out_last;
    wire [95:0] lift_out_data;

    awb #(
        .R_GAIN_Q8(256),
        .G_GAIN_Q8(256),
        .B_GAIN_Q8(256),
        .SHARPEN_Q4(0)
    ) lift_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(in_last), .I_tuser(in_user), .I_tdata(in_data),
        .I_tvalid(in_valid), .I_tready(lift_in_ready),
        .O_tlast(lift_out_last), .O_tuser(lift_out_user), .O_tdata(lift_out_data),
        .O_tvalid(lift_out_valid), .O_tready(1'b1)
    );

    awb #(
        .R_GAIN_Q8(384),
        .G_GAIN_Q8(256),
        .B_GAIN_Q8(128),
        .SHARPEN_Q4(0)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(in_last), .I_tuser(in_user), .I_tdata(in_data),
        .I_tvalid(in_valid), .I_tready(in_ready),
        .O_tlast(out_last), .O_tuser(out_user), .O_tdata(out_data),
        .O_tvalid(out_valid), .O_tready(out_ready)
    );

    task send_word;
        input [95:0] data;
        input        user;
        input        last;
        begin
            @(negedge clk);
            while (!in_ready) @(negedge clk);
            in_data = data;
            in_user = user;
            in_last = last;
            in_valid = 1'b1;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
            in_user = 1'b0;
            in_last = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        send_word({24'hf0f0f0, 24'h808080, 24'h101010, 24'h204060}, 1'b1, 1'b1);
        if (!out_valid || !out_user || !out_last)
            $fatal(1, "AWB output sideband mismatch");
        if (!lift_out_valid || !lift_out_user || !lift_out_last ||
            lift_out_data[47:24] !== 24'h474747)
            $fatal(1, "neutral lift mismatch: %h", lift_out_data[47:24]);
        if (out_data[23:16] !== 8'h78 || out_data[15:8] !== 8'h89 || out_data[7:0] !== 8'h78)
            $fatal(1, "lane0 gain result mismatch: %h", out_data[23:0]);
        if (out_data[47:40] !== 8'h56 || out_data[39:32] !== 8'h47 || out_data[31:24] !== 8'h32)
            $fatal(1, "lane1 gain result mismatch: %h", out_data[47:24]);
        if (out_data[95:88] !== 8'hf4 || out_data[87:80] !== 8'hf0 || out_data[79:72] !== 8'hb6)
            $fatal(1, "highlight compression result mismatch: %h", out_data[95:72]);
        if (!(out_data[95:72] > out_data[71:48]) || out_data[95:72] >= 24'hffffff)
            $fatal(1, "highlight mapping is not monotonic");

        // Black must remain black; the curve is intended for shadows and mid-tones.
        send_word({24'h000000, 24'h404040, 24'h202020, 24'h000000}, 1'b0, 1'b0);
        if (!lift_out_valid || lift_out_data[23:0] !== 24'h000000)
            $fatal(1, "black level was lifted: %h", lift_out_data[23:0]);

        // Load a processed beat, then hold it while the consumer is stalled.
        send_word({24'h202020, 24'h404040, 24'h606060, 24'h808080}, 1'b0, 1'b0);
        @(negedge clk);
        out_ready = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!out_valid || out_data !== 96'h786347a58963c6a578e0bc89)
                $fatal(1, "AWB output changed during stall: %h", out_data);
        end
        @(negedge clk);
        out_ready = 1'b1;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "stalled AWB beat was repeated");

        $display("PASS awb_enhance: lane order, fixed gain, saturation, highlight and stall stability");
        $finish;
    end
endmodule
