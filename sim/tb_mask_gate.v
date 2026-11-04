`timescale 1ns/1ps
module tb_mask_gate;
    reg alive=1'b1, candidate=1'b1, hit=1'b1;
    reg [11:0] x=10, y=10, left=8, right=12, top=8, bottom=12;
    wire mask_hit;

    tracker_mask_gate dut(
        .source_alive(alive),.candidate_valid(candidate),.color_hit(hit),
        .x(x),.y(y),.left(left),.right(right),.top(top),.bottom(bottom),
        .mask_hit(mask_hit));

    task check;
        input [8*24-1:0] name;
        input expected;
        begin
            #1;
            if(mask_hit !== expected)
                $fatal(1,"%0s mask=%b expected=%b",name,mask_hit,expected);
        end
    endtask

    initial begin
        check("candidate HSV box hit",1'b1);
        x=13; check("outside candidate box",1'b0);
        x=10; candidate=0; check("no candidate",1'b0);
        candidate=1; hit=0; check("HSV mismatch",1'b0);
        hit=1; alive=0; check("black or stale source",1'b0);
        alive=1; x=8; y=12; check("inclusive box edges",1'b1);
        x=7; check("outside left edge",1'b0);
        $display("PASS mask gate: candidate, HSV, live source, and inclusive box qualification");
        $finish;
    end
endmodule
