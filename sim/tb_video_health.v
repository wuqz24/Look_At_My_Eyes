`timescale 1ns/1ps
module tb_video_health;
    reg clk=0,rst_n=0,frame_tick=0,tag_alive=0,tag_valid=0,de=0,rgb_nonzero=0;
    wire healthy,recovery,fault;
    always #5 clk=~clk;

    video_health #(.CLK_HZ(1000),.TIMEOUT_MS(20),.RECOVERY_FRAMES(2)) dut(
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.tag_alive(tag_alive),
        .tag_valid(tag_valid),.de(de),.rgb_nonzero(rgb_nonzero),
        .healthy(healthy),.recovery(recovery),.fault(fault));

    task pulse_frame;
        begin @(negedge clk); frame_tick=1; @(negedge clk); frame_tick=0; end
    endtask
    task pulse_tag;
        begin @(negedge clk); tag_alive=1; tag_valid=1; de=1; rgb_nonzero=1;
            @(negedge clk); tag_valid=0; de=0; rgb_nonzero=0; end
    endtask

    reg saw_recovery;
    always @(posedge clk)
        if (recovery) saw_recovery <= 1'b1;

    initial begin
        saw_recovery=1'b0;
        repeat(3) @(negedge clk); rst_n=1;
        repeat(5) @(negedge clk);
        if(healthy || !fault) $fatal(1,"health did not start in fault");
        pulse_frame; pulse_tag; pulse_frame; pulse_tag;
        repeat(3) begin
            @(negedge clk);
            if(recovery) saw_recovery=1'b1;
        end
        if(!healthy || !saw_recovery || fault) $fatal(1,"fresh frames did not recover video");
        @(negedge clk);
        if(recovery) $fatal(1,"recovery was not a pulse");
        repeat(30) @(negedge clk);
        if(healthy || !fault) $fatal(1,"stale tags did not force fault");
        pulse_frame; pulse_tag;
        if(healthy) $fatal(1,"single recovery frame was accepted");
        pulse_frame; pulse_tag;
        repeat(2) @(negedge clk);
        if(!healthy || fault) $fatal(1,"second fresh frame did not recover");
        $display("PASS video_health: stale timeout, two-frame recovery, one-cycle recovery pulse");
        $finish;
    end
endmodule
