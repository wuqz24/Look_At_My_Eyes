`timescale 1ns/1ps
// Simulation-only models for the generated NOREG synchronous-read BRAMs.
// READBEFOREWRITE is preserved by nonblocking writes. Never add to synthesis.
module blk_mem_gen_zhenghe (
    input [31:0] dia, input [10:0] addra, input wea, input clka,
    input [10:0] addrb, input clkb, output reg [31:0] dob
);
    reg [31:0] mem [0:2047];
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule

module blk_mem_gen_demosaic (
    input [32:0] dia, input [10:0] addra, input wea, input clka,
    input [10:0] addrb, input clkb, output reg [32:0] dob
);
    reg [32:0] mem [0:2047];
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule
