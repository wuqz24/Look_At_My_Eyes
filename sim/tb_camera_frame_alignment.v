`timescale 1ns/1ps

module tb_camera_frame_alignment;
    // Set to zero to reproduce the old top-level wiring.
    parameter EARLY_FRAME_START = 1;
    parameter INPUT_GAP = 0;
    reg camera_clk = 0, ddr_clk = 0, rst_n = 0;
    always #7 camera_clk = ~camera_clk;
    always #5 ddr_clk = ~ddr_clk;
    reg capture_start = 0, rgb_start = 0, rgb_last = 0, rgb_valid = 0;
    reg [95:0] rgb_data = 0;
    wire packed_start, packed_valid;
    wire [127:0] packed_data;
    wire wr_en, busy;
    wire [24:0] wr_addr;
    wire [127:0] wr_data;
    reg ready = 1;
    integer cycle = 0, frame = 0, sent = 0, received = 0, b, k;
    reg [24:0] base_addr;
    reg [127:0] expected;

    function [7:0] stream_byte;
        input integer offset;
        input integer frame_id;
        begin
            // Unequal R/G/B bytes expose a one-word (16-byte) phase slip.
            case (offset % 3)
                0: stream_byte = 8'hd0 + frame_id;
                1: stream_byte = 8'h40 + ((offset / 3) % 16);
                2: stream_byte = 8'h10 + ((offset / 48) % 16);
            endcase
        end
    endfunction

    data_96bit_to_128bit packer (
        .I_clk(camera_clk), .I_rst_n(rst_n),
        .I_96b_frame_start(rgb_start), .I_96b_line_end(rgb_last),
        .I_96b_valid(rgb_valid), .I_96b_data(rgb_data), .I_96b_ready(),
        .O_128b_frame_start(packed_start), .O_128b_line_end(),
        .O_128b_valid(packed_valid), .O_128b_data(packed_data), .O_128b_ready(1'b1)
    );
    video_in dut (
        .I_rst_n(rst_n), .I_camera_clk(camera_clk),
        .I_camera_frame_start(EARLY_FRAME_START ? capture_start : packed_start),
        .I_camera_valid(packed_valid), .I_camera_data(packed_data),
        .I_mipi_rx_error(1'b0), .I_ddr_clk(ddr_clk), .I_display_pause(1'b0),
        .I_video_out_rd_busy(1'b0), .O_video_in_wr_busy(busy), .O_video_out_rp(),
        .O_ddr_user_wr_en(wr_en), .O_ddr_user_addr(wr_addr),
        .O_ddr_user_wr_data(wr_data), .I_ddr_user_ready(ready)
    );

    always @(negedge ddr_clk) begin
        cycle = cycle + 1;
        ready = ((cycle % 7) != 2 && (cycle % 7) != 3);
    end
    always @(posedge ddr_clk) begin
        if (rst_n && wr_en) begin
            for (k = 0; k < 16; k = k + 1)
                expected[127-k*8 -: 8] = stream_byte(received*16+k, frame);
            if (wr_data !== expected)
                $fatal(1, "frame %0d word %0d: RGB byte alignment lost; expected %h got %h",
                    frame, received, expected, wr_data);
            if (wr_addr !== base_addr + received*8)
                $fatal(1, "frame %0d word %0d: wrong DDR address %0d", frame, received, wr_addr);
            if (!busy) $fatal(1, "write without arbitration busy");
            received = received + 1;
        end
    end

    initial begin
        #2000000;
        $fatal(1, "timeout: frame %0d received %0d/480 words", frame, received);
    end
    initial begin
        repeat (5) @(negedge camera_clk);
        rst_n = 1;
        for (frame = 0; frame < 8; frame = frame + 1) begin
            received = 0;
            base_addr = (frame % 4) * 7000000;
            @(negedge camera_clk);
            capture_start = 1;
            @(negedge camera_clk);
            capture_start = 0;
            // CSI frame start precedes the ISP's line-buffered RGB output.
            repeat (80 + frame) @(negedge camera_clk);
            for (sent = 0; sent < 640; sent = sent + 1) begin
                @(negedge camera_clk);
                rgb_valid = 1;
                rgb_start = (sent == 0);
                rgb_last = ((sent % 320) == 319);
                for (b = 0; b < 12; b = b + 1)
                    rgb_data[95-b*8 -: 8] = stream_byte(sent*12+b, frame);
                if (INPUT_GAP != 0) begin
                    @(negedge camera_clk);
                    rgb_valid = 0; rgb_start = 0; rgb_last = 0;
                    repeat (INPUT_GAP-1) @(negedge camera_clk);
                end
                if (sent == 319) begin
                    @(negedge camera_clk);
                    rgb_valid = 0; rgb_start = 0; rgb_last = 0;
                    repeat (50) @(negedge camera_clk);
                end
            end
            @(negedge camera_clk);
            rgb_valid = 0; rgb_start = 0; rgb_last = 0;
            wait (received == 480);
            repeat (60) @(negedge camera_clk);
            if (received != 480) $fatal(1, "extra frame words");
        end
        $display("PASS camera_frame_alignment: 8 frames, 3840 exact DDR words, RGB order, ready gaps and buffer wrap");
        $finish;
    end
endmodule

// Diagnostic-only entry point: expected to fail, never in the passing suite.
module tb_camera_frame_alignment_legacy;
    tb_camera_frame_alignment #(.EARLY_FRAME_START(0), .INPUT_GAP(1)) test();
endmodule
