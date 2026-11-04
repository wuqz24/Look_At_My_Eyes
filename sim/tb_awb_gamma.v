`timescale 1ns/1ps
module tb_awb_gamma;
    reg clk=0, rst_n=0, valid=0;
    reg [95:0] data=0;
    wire [95:0] result;
    wire out_valid;
    integer i, expected, encoded, previous, error;
    real linear_value, srgb;
    always #5 clk=~clk;
    awb dut(.I_clk(clk),.I_rst_n(rst_n),.I_tlast(1'b0),.I_tuser(1'b0),
        .I_tdata(data),.I_tvalid(valid),.I_tready(),.O_tlast(),.O_tuser(),
        .O_tdata(result),.O_tvalid(out_valid),.O_tready(1'b1));
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        previous=0;
        // Independent IEC sRGB reference; checks every quantization step.
        for(i=0;i<256;i=i+1) begin
            linear_value=i/255.0;
            if(linear_value<=0.0031308) srgb=12.92*linear_value;
            else srgb=1.055*(linear_value**(1.0/2.4))-0.055;
            encoded=$rtoi(srgb*255.0+0.5);
            expected=encoded>224 ? 224+((encoded-224)*64)/95 : encoded;
            @(negedge clk); valid=1; data={12{i[7:0]}};
            @(posedge clk); #1;
            error=$signed({1'b0,result[7:0]})-expected;
            if(!out_valid || error>2 || error< -2)
                $fatal(1,"linear-to-display mapping input=%0d got=%0d expected=%0d",i,result[7:0],expected);
            if(result!=={12{result[7:0]}} || result[7:0]<previous)
                $fatal(1,"gamma changes neutral balance or reverses a ramp at %0d",i);
            if(i==0 && result!==0) $fatal(1,"black pedestal added");
            previous=result[7:0];
        end
        if(result[7:0]!=244) $fatal(1,"highlight headroom lost");
        $display("PASS awb_gamma: 256-level sRGB reference, neutral balance, monotonicity and headroom");
        $finish;
    end
    initial begin #100000; $fatal(1,"gamma timeout"); end
endmodule
