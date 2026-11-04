`timescale 1ns/1ps
module tb_reset_sync;
    reg clk=0;
    reg arst_n=0;
    wire rst_n;
    always #5 clk=~clk;

    reset_sync #(.STAGES(2)) dut(.clk(clk),.arst_n(arst_n),.rst_n(rst_n));

    initial begin
        #2;
        if(rst_n!==1'b0) $fatal(1,"reset released before clock");
        arst_n=1'b1;
        #1;
        if(rst_n!==1'b0) $fatal(1,"reset released asynchronously");
        @(posedge clk); #1;
        if(rst_n!==1'b0) $fatal(1,"reset released after first stage");
        @(posedge clk); #1;
        if(rst_n!==1'b0) $fatal(1,"reset released too early");
        @(posedge clk); #1;
        if(rst_n!==1'b1) $fatal(1,"reset did not release after synchronizer stages");
        arst_n=1'b0; #1;
        if(rst_n!==1'b0) $fatal(1,"reset assertion was not immediate");
        $display("PASS reset_sync: asynchronous assertion and synchronous release");
        $finish;
    end
endmodule
