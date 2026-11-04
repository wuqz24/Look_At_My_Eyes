`timescale 1ns/1ps

module tb_video_in_ddr_ready_guard;
    reg rst_n = 1'b0;
    reg camera_clk = 1'b0;
    reg ddr_clk = 1'b0;
    always #7 camera_clk = ~camera_clk;
    always #5 ddr_clk = ~ddr_clk;

    reg camera_frame_start = 1'b0;
    reg camera_valid = 1'b0;
    reg [127:0] camera_data = 128'd0;
    reg ddr_user_ready = 1'b1;
    integer ready_cycle = 0;
    reg run_ready_pattern = 1'b0;

    wire camera_busy;
    wire [1:0] camera_rp;
    wire camera_wr_en;
    wire [24:0] camera_addr;
    wire [127:0] camera_wr_data;

    integer camera_writes_seen = 0;
    integer expected_word = 0;
    reg [24:0] expected_addr = 25'd0;
    integer timeout = 0;

    video_in dut (
        .I_rst_n(rst_n),
        .I_camera_clk(camera_clk),
        .I_camera_frame_start(camera_frame_start),
        .I_camera_valid(camera_valid),
        .I_camera_data(camera_data),
        .I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr_clk),
        .I_display_pause(1'b0),
        .I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(camera_busy),
        .O_video_out_rp(camera_rp),
        .O_ddr_user_wr_en(camera_wr_en),
        .O_ddr_user_addr(camera_addr),
        .O_ddr_user_wr_data(camera_wr_data),
        .I_ddr_user_ready(ddr_user_ready)
    );

    // This models the actual user request FIFO: ready controls whether the
    // producer launches another read, while an already asserted write enable
    // remains a valid request at the interface boundary.
    always @(negedge ddr_clk) begin
        if (!run_ready_pattern) begin
            ddr_user_ready = 1'b1;
        end else begin
            case (ready_cycle % 8)
                0, 1, 3, 6, 7: ddr_user_ready = 1'b1;
                default: ddr_user_ready = 1'b0;
            endcase
            ready_cycle = ready_cycle + 1;
        end
    end

    // Sample before nonblocking assignments at this edge, matching the
    // downstream FIFO's sampling of the registered user request.
    always @(posedge ddr_clk) begin
        if (camera_wr_en) begin
            if (!run_ready_pattern)
                $fatal(1, "write request appeared before ready-gap test started");
            if (camera_wr_data !== {8{expected_word[15:0]}})
                $fatal(1, "DDR write data mismatch at request %0d: expected %h got %h",
                    expected_word, {8{expected_word[15:0]}}, camera_wr_data);
            if (camera_addr !== expected_addr)
                $fatal(1, "DDR write address mismatch at request %0d: expected %0d got %0d",
                    expected_word, expected_addr, camera_addr);
            if (!camera_busy)
                $fatal(1, "camera write request was not covered by busy arbitration");
            camera_writes_seen = camera_writes_seen + 1;
            expected_word = expected_word + 1;
            expected_addr = expected_addr + 25'd8;
        end
    end

    task send_camera_burst;
        integer i;
        begin
            for (i = 0; i < 300; i = i + 1) begin
                @(negedge camera_clk);
                camera_data = {8{i[15:0]}};
                camera_valid = 1'b1;
            end
            @(negedge camera_clk);
            camera_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge camera_clk);
        rst_n = 1'b1;

        // The frame-start pulse resets the input FIFO before the test burst.
        @(negedge camera_clk);
        camera_frame_start = 1'b1;
        @(negedge camera_clk);
        camera_frame_start = 1'b0;
        repeat (30) @(posedge camera_clk);

        fork
            send_camera_burst();
            begin
                wait (dut.S_ddr_wr_valid && (dut.S_fifo_rd_num >= 9'd240));
                run_ready_pattern = 1'b1;
                ready_cycle = 0;
                while (camera_writes_seen < 240 && timeout < 4000) begin
                    @(posedge ddr_clk);
                    timeout = timeout + 1;
                end
            end
        join

        if (camera_writes_seen !== 240)
            $fatal(1, "expected 240 DDR writes, observed %0d (timeout %0d)",
                camera_writes_seen, timeout);

        $display("PASS video_in_ddr_ready_guard: write data/address remain aligned across ready gaps");
        $finish;
    end
endmodule
