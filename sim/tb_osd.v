`timescale 1ns/1ps
module tb_osd;
    reg clk=0,rst_n=0,ft=0;
    always #5 clk=~clk;
    reg [11:0] x=912,y=220;
    tracker_osd dut(.clk(clk),.rst_n(rst_n),.frame_tick(ft),.x(x),.y(y),
        .cx(12'd1279),.cy(12'd719),.area(13'd920),.mode(3'd2),.color(2'd1),.shape(2'd1),
        .valid(1'b1),.armed(1'b1),.alive(1'b1),.moving(1'b1),.overrun(1'b1),
        .analysis_cycles(32'h1234abcd),.latency_us(32'h0000abcd),.tag_valid(1'b1),
        .red_valid(1'b1),.green_valid(1'b0),.blue_valid(1'b0),
        .red_cx(12'h4a0),.red_cy(12'h2d0),.green_cx(0),.green_cy(0),.blue_cx(0),.blue_cy(0),
        .red_area(13'h120),.green_area(0),.blue_area(0),
        .red_shape(2'd1),.green_shape(2'd2),.blue_shape(2'd3),
        .red_confidence(8'h60),.green_confidence(0),.blue_confidence(0),.follow_enable(1'b1),
        .limit(1'b0),.red_hits(10'd123),.blue_hits(10'd45));

    task automatic expect_hit;
        input [11:0] sample_x;
        input [11:0] sample_y;
        input expected;
        begin
            x=sample_x;
            y=sample_y;
            #1;
            if(dut.text_hit !== expected)
                $fatal(1,"text_hit mismatch at (%0d,%0d): expected %b got %b",
                    sample_x,sample_y,expected,dut.text_hit);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        rst_n=1;
        ft=1;
        @(negedge clk);
        ft=0;
        repeat(2) @(negedge clk);

        // The first status row starts with the D in DETECTION.
        expect_hit(12'd918,12'd222,1'b1);
        expect_hit(12'd914,12'd222,1'b0);

        // Pixels outside the status panel must leave the video untouched.
        expect_hit(12'd900,12'd300,1'b0);
        expect_hit(12'd1264,12'd300,1'b0);
        expect_hit(12'd1000,12'd704,1'b0);

        // The status layer remains observable through the public pixel-level
        // hit output after the frame tick.
        expect_hit(12'd918,12'd238,1'b1);
        $display("PASS osd: title glyph, blank area and panel boundaries");
        $finish;
    end
endmodule
