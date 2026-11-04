`timescale 1ns/1ps

module tb_display_mode;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg frame_tick = 1'b0;
    reg sw1 = 1'b0;
    reg sw2 = 1'b0;
    reg [23:0] rgb_in = 24'h123456;
    reg [7:0] threshold = 8'd12;
    wire [1:0] mode;
    wire [23:0] rgb_out;

    always #5 clk = ~clk;

    display_mode dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_tick(frame_tick),
        .sw1(sw1),
        .sw2(sw2),
        .threshold(threshold),
        .rgb_in(rgb_in),
        .mode(mode),
        .rgb_out(rgb_out)
    );

    task pulse_frame;
        begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
        end
    endtask

    task wait_switch_sync;
        begin
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        if (mode !== 2'd0 || rgb_out !== rgb_in)
            $fatal(1, "reset default is not normal RGB");

        // SW1=1, SW2=0 selects grayscale, but only at the next frame.
        sw1 = 1'b1;
        sw2 = 1'b0;
        wait_switch_sync();
        if (mode !== 2'd0 || rgb_out !== rgb_in)
            $fatal(1, "switch changed display before frame boundary");
        pulse_frame();
        rgb_in = 24'h64321e;
        #1;
        if (mode !== 2'd1 || rgb_out !== 24'h3e3e3e)
            $fatal(1, "grayscale mode or luminance calculation failed: mode=%0d rgb=%h", mode, rgb_out);

        // SW2=1, SW1=0 selects binary.  12 is the low-light threshold edge.
        sw1 = 1'b0;
        sw2 = 1'b1;
        wait_switch_sync();
        if (mode !== 2'd1)
            $fatal(1, "grayscale mode changed before frame boundary");
        pulse_frame();
        rgb_in = 24'h0c0c0c;
        #1;
        if (mode !== 2'd2 || rgb_out !== 24'hffffff)
            $fatal(1, "binary threshold equality failed: mode=%0d rgb=%h", mode, rgb_out);
        rgb_in = 24'h0b0b0b;
        #1;
        if (rgb_out !== 24'h000000)
            $fatal(1, "binary low level failed: rgb=%h", rgb_out);

        // 11 is reserved and must return to normal RGB.
        sw1 = 1'b1;
        sw2 = 1'b1;
        wait_switch_sync();
        pulse_frame();
        rgb_in = 24'h123456;
        #1;
        if (mode !== 2'd0 || rgb_out !== rgb_in)
            $fatal(1, "reserved switch encoding did not fall back to RGB");

        $display("PASS display_mode: synchronized switches, frame-boundary latch, grayscale and binary");
        $finish;
    end
endmodule
