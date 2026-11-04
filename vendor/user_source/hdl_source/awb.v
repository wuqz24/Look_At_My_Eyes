// Lightweight RGB enhancement stage for the SC500 stream.
// The input and output contain four RGB888 pixels packed as {pixel3..pixel0}.
module awb #(
    parameter integer IMG_HEIGHT = 1080,
    parameter integer IMG_WIDTH  = 1920,
    parameter integer R_GAIN_Q8  = 256,
    parameter integer G_GAIN_Q8  = 256,
    parameter integer B_GAIN_Q8  = 256,
    parameter integer HIGHLIGHT_START = 224,
    parameter integer HIGHLIGHT_FLOOR = 160,
    parameter integer SHARPEN_Q4 = 2
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    input  wire        O_tready
);
    function [7:0] clamp8;
        input integer value;
        begin
            if (value < 0)
                clamp8 = 8'd0;
            else if (value > 255)
                clamp8 = 8'd255;
            else
                clamp8 = value[7:0];
        end
    endfunction

    function [7:0] gain8;
        input [7:0] value;
        input integer gain_q8;
        integer scaled;
        begin
            scaled = (value * gain_q8) >> 8;
            gain8 = clamp8(scaled);
        end
    endfunction

    // Linear sensor RGB needs display encoding, not a small linear lift.
    // IEC 61966-2-1 sRGB OETF, rounded to 8 bits. Entry 0 is the low byte.
    // Constant lookup: no runtime power/division and no external ROM file.
    localparam [2047:0] SRGB_LUT = {
        128'hfffffefefdfdfcfcfbfbfbfafaf9f9f8,
        128'hf8f7f7f6f6f6f5f5f4f4f3f3f2f2f1f1,
        128'hf0f0efefeeeeeeededececebebeaeae9,
        128'he9e8e8e7e7e6e6e5e5e4e4e3e3e2e2e1,
        128'he0e0dfdfdededddddcdcdbdbdadad9d8,
        128'hd8d7d7d6d6d5d5d4d4d3d2d2d1d1d0d0,
        128'hcfcececdcdcccbcbcacac9c8c8c7c7c6,
        128'hc5c5c4c4c3c2c2c1c0c0bfbebebdbdbc,
        128'hbbbbbab9b9b8b7b6b6b5b4b4b3b2b2b1,
        128'hb0afafaeadadacabaaaaa9a8a7a7a6a5,
        128'ha4a3a3a2a1a09f9f9e9d9c9b9b9a9998,
        128'h9796959494939291908f8e8d8c8b8a89,
        128'h8887868584838281807f7e7d7c7a7978,
        128'h777675737271706e6d6c6a6968666563,
        128'h62605f5d5c5a58565553514f4d4b4947,
        128'h4542403d3b3835322e2a26221c160d00
    };

    function [7:0] brightness8;
        input [7:0] value;
        begin
            brightness8 = SRGB_LUT[{value,3'b000} +: 8];
        end
    endfunction

    // Keep the knee continuous at HIGHLIGHT_START and reduce the slope above
    // it.  With the default parameters, 255 maps to 244 instead of clipping.
    function [7:0] highlight8;
        input [7:0] value;
        integer mapped;
        begin
            if (value <= HIGHLIGHT_START)
                highlight8 = value;
            else if ((HIGHLIGHT_START == 224) && (HIGHLIGHT_FLOOR == 160)) begin
                mapped = HIGHLIGHT_START + (((value - HIGHLIGHT_START) * 64) / 95);
                highlight8 = clamp8(mapped);
            end else begin
                mapped = HIGHLIGHT_START +
                    ((value - HIGHLIGHT_START) * (HIGHLIGHT_START - HIGHLIGHT_FLOOR)) /
                    (255 - HIGHLIGHT_FLOOR);
                highlight8 = clamp8(mapped);
            end
        end
    endfunction

    function [7:0] enhance8;
        input [7:0] value;
        input integer gain_q8;
        begin
            enhance8 = highlight8(brightness8(gain8(value, gain_q8)));
        end
    endfunction

    assign I_tready = ~O_tvalid || O_tready;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_tdata  <= 96'd0;
        end else if (I_tready) begin
            if (I_tvalid) begin
                O_tvalid <= 1'b1;
                O_tuser  <= I_tuser;
                O_tlast  <= I_tlast;
                O_tdata  <= {
                    enhance8(I_tdata[95:88], R_GAIN_Q8),
                    enhance8(I_tdata[87:80], G_GAIN_Q8),
                    enhance8(I_tdata[79:72], B_GAIN_Q8),
                    enhance8(I_tdata[71:64], R_GAIN_Q8),
                    enhance8(I_tdata[63:56], G_GAIN_Q8),
                    enhance8(I_tdata[55:48], B_GAIN_Q8),
                    enhance8(I_tdata[47:40], R_GAIN_Q8),
                    enhance8(I_tdata[39:32], G_GAIN_Q8),
                    enhance8(I_tdata[31:24], B_GAIN_Q8),
                    enhance8(I_tdata[23:16], R_GAIN_Q8),
                    enhance8(I_tdata[15:8],  G_GAIN_Q8),
                    enhance8(I_tdata[7:0],   B_GAIN_Q8)
                };
            end else begin
                O_tvalid <= 1'b0;
                O_tuser  <= 1'b0;
                O_tlast  <= 1'b0;
                O_tdata  <= 96'd0;
            end
        end
    end
endmodule
