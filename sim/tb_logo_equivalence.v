`timescale 1ns/1ps
module tb_logo_equivalence;
    reg [7:0] x, y;
    wire [14:0] addr = y * 15'd160 + x;
    wire [24:0] reference_pixel;
    wire hit;
    wire [23:0] pixel;
    integer ix, iy, count;
    anlogic_logo_rom reference_rom(addr, reference_pixel);
    anlogic_logo_compact dut(x, y, hit, pixel);
    initial begin
        count = 0;
        for (iy=0; iy<160; iy=iy+1)
            for (ix=0; ix<160; ix=ix+1) begin
                x=ix; y=iy; #1;
                if (hit !== reference_pixel[24] ||
                    (hit && pixel !== reference_pixel[23:0]))
                    $fatal(1,"Logo mismatch at %0d,%0d",ix,iy);
                if (hit) count=count+1;
            end
        if (count != 6387) $fatal(1,"Unexpected opaque pixel count %0d",count);
        $display("PASS logo: all 25600 pixels match original ROM, 6387 opaque");
        $finish;
    end
endmodule
