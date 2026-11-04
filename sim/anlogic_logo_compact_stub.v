// Simulation-only stand-in for the tracking-loop testbench.
//
// rtl/anlogic_logo_compact.v contains a very large sparse case table that makes
// xsim spend minutes of CPU per test run.  The logo is unrelated to the
// detector / servo / mask paths, so the closed-loop regression links this stub
// instead of the real decoder.  Synthesised builds must always use
// rtl/anlogic_logo_compact.v.
`timescale 1ns/1ps
module anlogic_logo_compact (
    input wire clk,
    input wire rst_n,
    input wire [7:0] x,
    input wire [7:0] y,
    output wire hit,
    output reg [23:0] pixel
);
    assign hit = 1'b0;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pixel <= 24'd0;
        else pixel <= 24'd0;
endmodule
