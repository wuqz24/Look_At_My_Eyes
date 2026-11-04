`timescale 1ns/1ps

module tb_data96_128_contract;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg        in_frame_start = 1'b0;
    reg        in_line_end = 1'b0;
    reg        in_valid = 1'b0;
    reg [95:0] in_data = 96'd0;
    wire       in_ready;
    wire       out_frame_start;
    wire       out_line_end;
    wire       out_valid;
    wire [127:0] out_data;
    reg        out_ready = 1'b1;

    data_96bit_to_128bit dut (
        .I_clk(clk),
        .I_rst_n(rst_n),
        .I_96b_frame_start(in_frame_start),
        .I_96b_line_end(in_line_end),
        .I_96b_valid(in_valid),
        .I_96b_data(in_data),
        .I_96b_ready(in_ready),
        .O_128b_frame_start(out_frame_start),
        .O_128b_line_end(out_line_end),
        .O_128b_valid(out_valid),
        .O_128b_data(out_data),
        .O_128b_ready(out_ready)
    );

    task drive_word;
        input [95:0] data;
        input frame_start;
        input line_end;
        begin
            @(negedge clk);
            in_data = data;
            in_frame_start = frame_start;
            in_line_end = line_end;
            in_valid = 1'b1;
        end
    endtask

    task check_output;
        input [127:0] expected_data;
        input expected_frame_start;
        input expected_line_end;
        begin
            if (!out_valid || out_data !== expected_data ||
                out_frame_start !== expected_frame_start ||
                out_line_end !== expected_line_end)
                $fatal(1, "output mismatch: valid=%b data=%h user=%b last=%b",
                    out_valid, out_data, out_frame_start, out_line_end);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        drive_word(96'h000102030405060708090a0b, 1'b1, 1'b0);
        @(posedge clk); #1;
        if (out_valid) $fatal(1, "unexpected output for first input beat");

        drive_word(96'h0c0d0e0f1011121314151617, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(128'h000102030405060708090a0b0c0d0e0f, 1'b1, 1'b0);

        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b0;
        repeat (2) begin
            @(posedge clk); #1;
            check_output(128'h000102030405060708090a0b0c0d0e0f, 1'b1, 1'b0);
        end

        @(negedge clk);
        out_ready = 1'b1;
        drive_word(96'h18191a1b1c1d1e1f20212223, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(128'h101112131415161718191a1b1c1d1e1f, 1'b0, 1'b0);

        // A blocked output must also block its completing input beat without
        // consuming or changing that beat. Releasing the sink accepts it once.
        @(negedge clk);
        out_ready = 1'b0;
        drive_word(96'h2425262728292a2b2c2d2e2f, 1'b0, 1'b1);
        @(posedge clk); #1;
        if (in_ready) $fatal(1, "input accepted while output was blocked");
        if (!in_valid || in_data !== 96'h2425262728292a2b2c2d2e2f || !in_line_end)
            $fatal(1, "upstream beat changed while ready was low");
        check_output(128'h101112131415161718191a1b1c1d1e1f, 1'b0, 1'b0);

        @(negedge clk);
        out_ready = 1'b1;
        @(posedge clk); #1;
        check_output(128'h202122232425262728292a2b2c2d2e2f, 1'b0, 1'b1);
        in_valid = 1'b0;

        // Continue directly into another four-beat group to check that the
        // packer returns to the same phase and sustains consecutive groups.
        drive_word(96'h303132333435363738393a3b, 1'b0, 1'b0);
        @(posedge clk); #1;
        if (out_valid) $fatal(1, "unexpected output at first beat of next group");

        drive_word(96'h3c3d3e3f4041424344454647, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(128'h303132333435363738393a3b3c3d3e3f, 1'b0, 1'b0);

        drive_word(96'h48494a4b4c4d4e4f50515253, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(128'h404142434445464748494a4b4c4d4e4f, 1'b0, 1'b0);

        drive_word(96'h5455565758595a5b5c5d5e5f, 1'b0, 1'b1);
        @(posedge clk); #1;
        check_output(128'h505152535455565758595a5b5c5d5e5f, 1'b0, 1'b1);

        @(negedge clk);
        in_valid = 1'b0;
        @(posedge clk); #1;
        if (out_valid) $fatal(1, "unexpected extra output beat");

        // A line may end with a partial 128-bit group. The residual bytes
        // must not be carried into the first pixels of the next line.
        drive_word(96'h606162636465666768696a6b, 1'b1, 1'b0);
        @(posedge clk); #1;
        if (out_valid) $fatal(1, "unexpected output at short-line first beat");

        drive_word(96'h6c6d6e6f7071727374757677, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(128'h606162636465666768696a6b6c6d6e6f, 1'b1, 1'b0);

        drive_word(96'h78797a7b7c7d7e7f80818283, 1'b0, 1'b1);
        @(posedge clk); #1;
        check_output(128'h707172737475767778797a7b7c7d7e7f, 1'b0, 1'b1);

        drive_word(96'h909192939495969798999a9b, 1'b0, 1'b0);
        @(posedge clk); #1;
        if (out_valid) $fatal(1, "line residual leaked into next line: %h", out_data);
        in_valid = 1'b0;

        $display("PASS data96_128_contract: continuous RGB packing, sideband and bidirectional stall stability");
        $finish;
    end
endmodule
