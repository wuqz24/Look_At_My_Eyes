`timescale 1ns/1ps

module tb_video_out_fifo_guard;
    reg rst_n = 1'b0;
    reg ddr_rst_n = 1'b0;
    reg dsi_rst_n = 1'b0;
    reg ddr_clk = 1'b0;
    reg dsi_clk = 1'b0;
    always #7 ddr_clk = ~ddr_clk;
    always #5 dsi_clk = ~dsi_clk;

    reg video_vsync = 1'b0;
    reg video_rd_en = 1'b0;
    reg ddr_rd_valid = 1'b0;
    reg [127:0] ddr_rd_data = 128'd0;
    reg [511:0] expected_pixel_bytes;
    reg [23:0] expected_pixel;
    wire ddr_rd_en;
    wire [24:0] ddr_addr;
    wire video_busy;
    wire [23:0] video_data;
    reg camera_frame_start = 1'b0;
    reg camera_valid = 1'b0;
    reg [127:0] camera_data = 128'd0;
    integer camera_word;
    reg monitor_camera_writes = 1'b0;
    integer camera_writes_seen = 0;
    integer expected_camera_word = 0;
    wire camera_busy;
    wire [1:0] camera_rp;
    wire camera_wr_en;
    wire [24:0] camera_addr;
    wire [127:0] camera_wr_data;

    video_in camera_dut (
        .I_rst_n(rst_n),
        .I_camera_clk(ddr_clk),
        .I_camera_frame_start(camera_frame_start),
        .I_camera_valid(camera_valid),
        .I_camera_data(camera_data),
        .I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr_clk),
        .I_display_pause(1'b0),
        .I_video_out_rd_busy(video_busy),
        .O_video_in_wr_busy(camera_busy),
        .O_video_out_rp(camera_rp),
        .O_ddr_user_wr_en(camera_wr_en),
        .O_ddr_user_addr(camera_addr),
        .O_ddr_user_wr_data(camera_wr_data),
        .I_ddr_user_ready(1'b1)
    );

    video_out dut (
        .I_rst_n(rst_n),
        .I_ddr_rst_n(ddr_rst_n),
        .I_dsi_rst_n(dsi_rst_n),
        .I_ddr_clk(ddr_clk),
        .O_video_out_rd_busy(video_busy),
        .I_video_in_wr_busy(camera_busy),
        .I_video_out_rp(2'd0),
        .O_ddr_user_rd_en(ddr_rd_en),
        .O_ddr_user_addr(ddr_addr),
        .I_ddr_user_ready(1'b1),
        .I_ddr_user_rd_valid(ddr_rd_valid),
        .I_ddr_user_rd_data(ddr_rd_data),
        .I_dsi_clk(dsi_clk),
        .I_video_vsync(video_vsync),
        .I_video_rd_en(video_rd_en),
        .O_vdieo_data(video_data)
    );

    always @(posedge ddr_clk) begin
        if ((camera_dut.S_fifo_rd_num >= 9'd240) && !camera_dut.S_fifo_rst &&
            !camera_busy)
            $fatal(1, "camera pending burst was not announced to DDR arbitration");
        if (monitor_camera_writes && camera_wr_en) begin
            if (!camera_busy)
                $fatal(1, "camera DDR write was not covered by busy arbitration");
            if (ddr_rd_en)
                $fatal(1, "DDR read and camera write were requested together");
            if (camera_wr_data !== {8{expected_camera_word[15:0]}})
                $fatal(1, "camera DDR word %0d misaligned: %h",
                    expected_camera_word, camera_wr_data);
            camera_writes_seen = camera_writes_seen + 1;
            expected_camera_word = expected_camera_word + 1;
        end
    end

    task check_empty_does_not_read;
        integer i;
        begin
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge dsi_clk); #1;
                if (dut.S_fifo_rd_en !== 1'b0)
                    $fatal(1, "video_out read an empty FIFO at cycle %0d", i);
                if (video_data !== 24'd0)
                    $fatal(1, "empty FIFO leaked stale data %h", video_data);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge dsi_clk);
        rst_n = 1'b1;
        ddr_rst_n = 1'b1;
        dsi_rst_n = 1'b1;

        video_rd_en = 1'b1;
        check_empty_does_not_read();
        video_rd_en = 1'b0;
        repeat (3) @(posedge dsi_clk);

        // An empty FIFO at the start of an active frame must not start showing
        // a partially arrived frame later in that same active region.
        @(negedge dsi_clk);
        video_vsync = 1'b1;
        repeat (3) @(negedge dsi_clk);
        video_vsync = 1'b0;
        repeat (20) @(posedge ddr_clk);
        @(negedge dsi_clk);
        video_rd_en = 1'b1;
        repeat (4) begin
            @(posedge dsi_clk); #1;
            if (video_data !== 24'd0)
                $fatal(1, "empty frame was not held black: %h", video_data);
        end

        // Arriving data cannot revive the rejected frame.
        @(negedge ddr_clk);
        ddr_rd_data = 128'h112233445566778899aabbccddeeff00;
        ddr_rd_valid = 1'b1;
        @(negedge ddr_clk);
        ddr_rd_data = 128'h0102030405060708090a0b0c0d0e0f10;
        @(negedge ddr_clk);
        ddr_rd_data = 128'h1112131415161718191a1b1c1d1e1f20;
        @(negedge ddr_clk);
        ddr_rd_valid = 1'b0;
        repeat (8) begin
            @(posedge dsi_clk); #1;
            if (video_data !== 24'd0)
                $fatal(1, "late FIFO data revived a rejected frame: %h", video_data);
        end

        // Start a fresh frame and prefill during blanking. The frame gate
        // must admit it only after the production prefill threshold is met.
        @(negedge dsi_clk);
        video_rd_en = 1'b0;
        video_vsync = 1'b1;
        repeat (3) @(negedge dsi_clk);
        video_vsync = 1'b0;
        repeat (20) @(posedge ddr_clk);

        for (camera_word = 0; camera_word < 240; camera_word = camera_word + 1) begin
            @(negedge ddr_clk);
            case (camera_word)
                0: ddr_rd_data = 128'h112233445566778899aabbccddeeff00;
                1: ddr_rd_data = 128'h0102030405060708090a0b0c0d0e0f10;
                2: ddr_rd_data = 128'h1112131415161718191a1b1c1d1e1f20;
                3: ddr_rd_data = 128'h00030000000300000003000000030000;
                default: ddr_rd_data = {8{camera_word[15:0]}};
            endcase
            ddr_rd_valid = 1'b1;
        end
        @(negedge ddr_clk);
        ddr_rd_valid = 1'b0;
        repeat (8) @(posedge dsi_clk);

        @(negedge dsi_clk);
        video_rd_en = 1'b1;
        repeat (2) @(posedge dsi_clk);
        if (!dut.S_frame_display_valid || !dut.S_frame_decision_made)
            $fatal(1, "prefilled frame was not admitted");
        if (dut.S_fifo_rd_num >= 9'd240)
            $fatal(1, "prefilled frame did not start FIFO reads");

        expected_pixel_bytes = {
            128'h112233445566778899aabbccddeeff00,
            128'h0102030405060708090a0b0c0d0e0f10,
            128'h1112131415161718191a1b1c1d1e1f20,
            128'h00030000000300000003000000030000
        };
        expected_pixel_bytes = expected_pixel_bytes << 24;
        for (camera_word = 0; camera_word < 16; camera_word = camera_word + 1) begin
            @(posedge dsi_clk); #1;
            expected_pixel = expected_pixel_bytes[511:488];
            if (video_data !== expected_pixel)
                $fatal(1, "RGB byte stream mismatch at pixel %0d: expected %h got %h",
                    camera_word, expected_pixel, video_data);
            expected_pixel_bytes = expected_pixel_bytes << 24;
        end

        repeat (20) begin
            @(posedge dsi_clk); #1;
            if (dut.S_fifo_emtpy && (dut.S_fifo_rd_cnt_1d >= 6) && video_data !== 24'd0)
                $fatal(1, "stale FIFO data repeated after empty: %h", video_data);
        end

        // A pixel-domain reset must blank the output immediately and must
        // not allow words already in the asynchronous FIFO to leak later.
        dsi_rst_n = 1'b0;
        #1;
        if (video_data !== 24'd0)
            $fatal(1, "pixel-domain reset did not blank video output");
        repeat (3) @(posedge dsi_clk);
        dsi_rst_n = 1'b1;
        repeat (3) @(posedge dsi_clk); #1;
        if (video_data !== 24'd0)
            $fatal(1, "pixel-domain reset leaked stale FIFO data");

        // The input FIFO request, returned data and DDR write enable must
        // remain aligned across a complete 240-word burst.
        @(negedge ddr_clk);
        camera_frame_start = 1'b1;
        repeat (3) @(negedge ddr_clk);
        camera_frame_start = 1'b0;
        repeat (20) @(negedge ddr_clk);
        monitor_camera_writes = 1'b1;
        fork
            begin
                for (camera_word = 0; camera_word < 300; camera_word = camera_word + 1) begin
                    @(negedge ddr_clk);
                    camera_data = {8{camera_word[15:0]}};
                    camera_valid = 1'b1;
                end
                @(negedge ddr_clk);
                camera_valid = 1'b0;
            end
            begin : wait_for_camera_burst
                integer timeout;
                timeout = 0;
                while (camera_writes_seen < 240 && timeout < 1000) begin
                    @(negedge ddr_clk);
                    ddr_rd_valid = ddr_rd_en;
                    ddr_rd_data = {8{timeout[15:0]}};
                    timeout = timeout + 1;
                end
                ddr_rd_valid = 1'b0;
                if (camera_writes_seen != 240)
                    $fatal(1, "camera FIFO burst stalled after %0d writes (camera_busy=%b video_busy=%b fifo_words=%0d read_valid=%b read_count=%0d)",
                        camera_writes_seen, camera_busy, video_busy,
                        camera_dut.S_fifo_rd_num, dut.S_ddr_rd_valid, dut.S_ddr_rd_cnt);
            end
        join
        monitor_camera_writes = 1'b0;

        $display("PASS video_fifo_guard: frame-stable underflow, prefill admission and camera burst alignment");
        $finish;
    end
endmodule
