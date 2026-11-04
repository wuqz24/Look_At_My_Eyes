`timescale 1ns/1ps

module tb_video_out_frame_reset_guard;
    localparam [127:0] OLD_WORD = 128'hA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5;
    localparam [127:0] NEW_WORD = 128'h5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A;

    reg rst_n = 1'b0;
    reg ddr_rst_n = 1'b0;
    reg dsi_rst_n = 1'b0;
    reg ddr_clk = 1'b0;
    reg dsi_clk = 1'b0;
    always #5 ddr_clk = ~ddr_clk;
    always #7 dsi_clk = ~dsi_clk;

    reg video_vsync = 1'b0;
    reg video_rd_en = 1'b0;
    wire ddr_rd_en;
    wire [24:0] ddr_addr;
    wire video_busy;
    reg ddr_rd_valid = 1'b0;
    reg [127:0] ddr_rd_data = 128'd0;
    reg request_epoch = 1'b0;
    reg frame_epoch = 1'b0;
    reg [31:0] request_count = 0;
    reg [31:0] first_burst_count = 0;
    reg [31:0] second_burst_count = 0;
    integer frame_start_rd_requests = 0;

    reg [31:0] valid_pipe = 0;
    reg [127:0] data_pipe [0:31];
    integer i;
    integer timeout;
    integer output_count;
    reg saw_old_word;
    reg saw_new_word;

    video_out dut (
        .I_rst_n(rst_n),
        .I_ddr_rst_n(ddr_rst_n),
        .I_dsi_rst_n(dsi_rst_n),
        .I_ddr_clk(ddr_clk),
        .O_video_out_rd_busy(video_busy),
        .I_video_in_wr_busy(1'b0),
        .I_video_out_rp(2'd0),
        .O_ddr_user_rd_en(ddr_rd_en),
        .O_ddr_user_addr(ddr_addr),
        .I_ddr_user_ready(1'b1),
        .I_ddr_user_rd_valid(ddr_rd_valid),
        .I_ddr_user_rd_data(ddr_rd_data),
        .I_dsi_clk(dsi_clk),
        .I_video_vsync(video_vsync),
        .I_video_rd_en(video_rd_en),
        .O_vdieo_data()
    );

    // Fixed response latency leaves requests outstanding when a display
    // frame starts. Each response keeps the epoch of its original request.
    always @(posedge ddr_clk) begin
        valid_pipe[0] <= ddr_rd_en;
        data_pipe[0] <= request_epoch ? NEW_WORD : OLD_WORD;
        for (i = 1; i < 32; i = i + 1) begin
            valid_pipe[i] <= valid_pipe[i-1];
            data_pipe[i] <= data_pipe[i-1];
        end
        ddr_rd_valid <= valid_pipe[31];
        ddr_rd_data <= data_pipe[31];

        if (ddr_rd_en) begin
            request_count <= request_count + 1;
            if (!frame_epoch)
                first_burst_count <= first_burst_count + 1;
            else
                second_burst_count <= second_burst_count + 1;
            if (dut.S_video_frame_start)
                frame_start_rd_requests <= frame_start_rd_requests + 1;
        end
    end

    task start_display_frame;
        begin
            @(negedge dsi_clk);
            video_vsync = 1'b1;
            repeat (3) @(negedge dsi_clk);
            video_vsync = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge ddr_clk);
        rst_n = 1'b1;
        ddr_rst_n = 1'b1;
        dsi_rst_n = 1'b1;

        // Allow the first prefetch to issue its complete 240-request burst.
        wait (first_burst_count == 240);

        // The response pipeline still contains old-frame reads here. The
        // external frame boundary is the point after which new requests use
        // NEW_WORD, while old outstanding responses remain OLD_WORD.
        @(negedge ddr_clk);
        frame_epoch = 1'b1;
        request_epoch = 1'b1;
        start_display_frame();

        repeat (4) @(posedge ddr_clk);
        if (frame_start_rd_requests != 0)
            $fatal(1, "DDR read request was issued while frame FIFO reset was active");

        // The display decision uses the read-domain count, which trails the
        // DDR write-domain count through the FIFO pointer synchronizer.
        wait (dut.S_fifo_rd_num >= 9'd240);
        @(negedge dsi_clk);
        video_rd_en = 1'b1;

        timeout = 0;
        output_count = 0;
        saw_old_word = 1'b0;
        saw_new_word = 1'b0;
        while (!saw_old_word && !saw_new_word && timeout < 5000) begin
            @(posedge dsi_clk); #1;
            if (dut.S_video_rd_en_1d && dut.S_frame_display_enable) begin
                output_count = output_count + 1;
                if (dut.O_vdieo_data === 24'hA5A5A5)
                    saw_old_word = 1'b1;
                if (dut.O_vdieo_data === 24'h5A5A5A)
                    saw_new_word = 1'b1;
            end
            timeout = timeout + 1;
        end

        if (saw_old_word)
            $fatal(1, "old DDR response was displayed after frame FIFO reset (outputs %0d)",
                output_count);
        if (!saw_new_word)
            $fatal(1, "new frame produced no visible DDR data (outputs %0d, second requests %0d)",
                output_count, second_burst_count);

        $display("PASS video_out_frame_reset_guard: frame reset excludes outstanding old DDR responses");
        $finish;
    end
endmodule
