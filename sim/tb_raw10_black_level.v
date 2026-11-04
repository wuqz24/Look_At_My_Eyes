`timescale 1ns/1ps

module tb_raw10_black_level;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg        in_valid = 1'b0;
    reg        in_user = 1'b0;
    reg        in_last = 1'b0;
    reg [39:0] in_data = 40'd0;
    wire       in_ready;
    wire       out_valid;
    wire       out_user;
    wire       out_last;
    wire [39:0] out_data;
    reg        out_ready = 1'b1;

    raw10_black_level #(.BLACK_LEVEL(64)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(in_valid), .I_tuser(in_user), .I_tlast(in_last),
        .I_tdata(in_data), .I_tready(in_ready),
        .O_tvalid(out_valid), .O_tuser(out_user), .O_tlast(out_last),
        .O_tdata(out_data), .O_tready(out_ready)
    );

    task send_word;
        input [39:0] data;
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

        send_word({10'd1023, 10'd81, 10'd64, 10'd0}, 1'b1, 1'b1);
        if (!out_valid || !out_user || !out_last)
            $fatal(1, "sideband was not delayed with the accepted word");
        if (out_data !== {10'd959, 10'd17, 10'd0, 10'd0})
            $fatal(1, "black-level floor or lane arithmetic failed: %h", out_data);

        // Consume the first word before applying backpressure to the next one.
        @(negedge clk);
        out_ready = 1'b1;

        @(negedge clk);
        out_ready = 1'b0;
        send_word({10'd400, 10'd300, 10'd200, 10'd100}, 1'b0, 1'b0);
        repeat (1) begin
            @(posedge clk);
            #1;
            if (!out_valid || out_data !== {10'd336, 10'd236, 10'd136, 10'd36})
                $fatal(1, "output changed or disappeared while stalled: %h", out_data);
        end

        @(negedge clk);
        out_ready = 1'b1;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "stalled word was presented more than once");

        $display("PASS raw10_black_level: four lanes, floor saturation, sideband and stall stability");
        $finish;
    end
endmodule
