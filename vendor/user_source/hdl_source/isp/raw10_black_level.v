// SC500 RAW10 black-level correction.
// The stream contains four pixels packed as {pixel3,pixel2,pixel1,pixel0}.
// This stage deliberately changes no Bayer phase or bit alignment.
module raw10_black_level #(
    parameter integer BLACK_LEVEL = 64,
    parameter integer PIXELS_PER_BEAT = 4
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [39:0] I_tdata,
    output wire        I_tready,
    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [39:0] O_tdata,
    input  wire        O_tready
);
    wire accept_in = I_tvalid && I_tready;
    wire accept_out = O_tvalid && O_tready;

    function [9:0] subtract_black;
        input [9:0] pixel;
        integer corrected;
        begin
            if (pixel <= BLACK_LEVEL)
                subtract_black = 10'd0;
            else begin
                corrected = pixel - BLACK_LEVEL;
                if (corrected > 1023)
                    subtract_black = 10'h3ff;
                else
                    subtract_black = corrected[9:0];
            end
        end
    endfunction

    assign I_tready = ~O_tvalid || O_tready;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_tdata  <= 40'd0;
        end else if (I_tready) begin
            if (I_tvalid) begin
                O_tvalid <= 1'b1;
                O_tuser  <= I_tuser;
                O_tlast  <= I_tlast;
                O_tdata  <= {
                    subtract_black(I_tdata[39:30]),
                    subtract_black(I_tdata[29:20]),
                    subtract_black(I_tdata[19:10]),
                    subtract_black(I_tdata[9:0])
                };
            end else begin
                O_tvalid <= 1'b0;
                O_tuser  <= 1'b0;
                O_tlast  <= 1'b0;
                O_tdata  <= 40'd0;
            end
        end
    end
endmodule
