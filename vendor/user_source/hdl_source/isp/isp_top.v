module isp_top (
    input  wire         axi4s_video_aclk,
    input  wire         I_rst_n,
    input  wire         I_tlast,
    input  wire         I_tuser,
    input  wire [39:0]  I_tdata,
    input  wire         I_tvalid,
    input  wire [9:0]   I_tdest,
    input  wire         O_tready,
    output wire [127:0] O_tdata,
    output wire         O_tlast,
    output wire         O_tuser,
    output wire         O_tvalid,
    output wire         I_tready
);
    wire        blc_tvalid;
    wire        raw_input_ready;
    wire        blc_output_ready;
    wire        blc_tuser;
    wire        blc_tlast;
    wire [39:0] blc_tdata;

    wire        demosaic_tvalid;
    wire        awb_input_ready;
    wire        demosaic_tuser;
    wire        demosaic_tlast;
    wire [127:0] demosaic_tdata;
    wire [95:0] rgb_tdata;

    wire        awb_tvalid;
    wire        awb_tready;
    wire        awb_tuser;
    wire        awb_tlast;
    wire [95:0] awb_tdata;

    wire        packed_tvalid;
    wire        packed_tuser;
    wire        packed_tlast;
    wire [127:0] packed_tdata;
    wire        packer_input_ready;

    assign O_tdata = packed_tdata;
    assign O_tvalid = packed_tvalid;
    assign O_tuser = packed_tuser;
    assign O_tlast = packed_tlast;

    raw10_black_level #(
        .BLACK_LEVEL(64)
    ) u_raw10_black_level (
        .I_clk(axi4s_video_aclk),
        .I_rst_n(I_rst_n),
        .I_tdata(I_tdata),
        .I_tvalid(I_tvalid),
        .I_tuser(I_tuser),
        .I_tlast(I_tlast),
        .I_tready(raw_input_ready),
        .O_tdata(blc_tdata),
        .O_tvalid(blc_tvalid),
        .O_tuser(blc_tuser),
        .O_tlast(blc_tlast),
        .O_tready(blc_output_ready)
    );

    demosaic #(
        .IMG_HEIGHT(720),
        .IMG_WIDTH(1280),
        .data_complete_delay(50),
        .BAYER_MODE("BGGR")
    ) u_demosaic (
        .I_clk(axi4s_video_aclk),
        .I_rst_n(I_rst_n),
        .axi4s_video_tdata(blc_tdata),
        .axi4s_video_tdest(I_tdest),
        .axi4s_video_tlast(blc_tlast),
        .axi4s_video_tvalid(blc_tvalid),
        .axi4s_video_tuser(blc_tuser),
        .axi4s_video_tready(blc_output_ready),
        .O_tlast(demosaic_tlast),
        .O_tuser(demosaic_tuser),
        .O_tdata(demosaic_tdata),
        .O_tvalid(demosaic_tvalid),
        .O_tready(awb_input_ready)
    );

    data128_96 u_data128_96 (
        .I_tdata(demosaic_tdata),
        .O_tdata(rgb_tdata)
    );

    awb #(
        .IMG_HEIGHT(720),
        .IMG_WIDTH(1280),
        .R_GAIN_Q8(256),
        .G_GAIN_Q8(256),
        .B_GAIN_Q8(256)
    ) u_awb (
        .I_clk(axi4s_video_aclk),
        .I_rst_n(I_rst_n),
        .I_tlast(demosaic_tlast),
        .I_tuser(demosaic_tuser),
        .I_tdata(rgb_tdata),
        .I_tvalid(demosaic_tvalid),
        .I_tready(awb_input_ready),
        .O_tlast(awb_tlast),
        .O_tuser(awb_tuser),
        .O_tdata(awb_tdata),
        .O_tvalid(awb_tvalid),
        .O_tready(awb_tready)
    );

    data_96bit_to_128bit u_data_96bit_to_128bit (
        .I_clk(axi4s_video_aclk),
        .I_rst_n(I_rst_n),
        .I_96b_frame_start(awb_tuser),
        .I_96b_line_end(awb_tlast),
        .I_96b_valid(awb_tvalid),
        .I_96b_data(awb_tdata),
        .I_96b_ready(packer_input_ready),
        .O_128b_frame_start(packed_tuser),
        .O_128b_line_end(packed_tlast),
        .O_128b_valid(packed_tvalid),
        .O_128b_data(packed_tdata),
        .O_128b_ready(O_tready)
    );

    assign awb_tready = packer_input_ready;
    assign I_tready = raw_input_ready;
endmodule
