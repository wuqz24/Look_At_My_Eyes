`timescale 1ns/1ps
module tb_buzzer;
    reg clk = 0;
    reg rst_n = 0;
    reg trigger = 0;
    wire buzzer;
    integer low_count;
    always #5 clk = ~clk;

    buzzer_one_shot #(.CLK_HZ(1000), .TONE_HZ(50), .DURATION_MS(10)) dut(
        .clk(clk), .rst_n(rst_n), .trigger(trigger), .buzzer(buzzer));

    initial begin
        repeat (3) @(posedge clk);
        if (buzzer !== 1'b1) $fatal(1, "buzzer was not idle-high during reset");
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        if (buzzer !== 1'b1) $fatal(1, "buzzer was not idle-high");
        @(negedge clk); trigger = 1'b1;
        @(negedge clk); trigger = 1'b0;
        low_count = 0;
        repeat (20) begin @(posedge clk); if (!buzzer) low_count = low_count + 1; end
        if (low_count == 0) $fatal(1, "trigger did not produce a low-active tone");
        trigger = 1'b1;
        repeat (4) @(posedge clk);
        trigger = 1'b0;
        repeat (20) @(posedge clk);
        if (buzzer !== 1'b1) $fatal(1, "buzzer did not return idle-high");
        $display("PASS buzzer_one_shot: reset idle, active-low tone, one-shot completion");
        $finish;
    end
endmodule
