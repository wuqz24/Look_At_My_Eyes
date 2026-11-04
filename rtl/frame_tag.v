module frame_tag_tx #(
    parameter integer TAG_WORD = 480
)(
    input wire clk, rst_n, capture_start, frame_start, valid,
    input wire [31:0] time_gray,
    input wire [127:0] data_in,
    output wire [127:0] data_out
);
    reg [31:0] gray_meta,gray_sync;
    reg [31:0] stamp,sequence;
    reg [17:0] word_count;
    function [31:0] ungray;
        input [31:0] g;
        integer i;
        begin
            ungray[31]=g[31];
            for(i=30;i>=0;i=i-1) ungray[i]=ungray[i+1]^g[i];
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gray_meta<=0; gray_sync<=0; stamp<=0; sequence<=0; word_count<=0;
        end else begin
            gray_meta<=time_gray; gray_sync<=gray_meta;
            if(capture_start) begin stamp<=ungray(gray_sync); sequence<=sequence+1'b1; end
            if(frame_start) word_count<=valid ? 1 : 0;
            else if(valid && word_count!=18'h3ffff) word_count<=word_count+1'b1;
        end
    end
    // Six pixels under the opaque logo region carry an in-band DDR frame identity.
    assign data_out=valid && !frame_start && word_count==TAG_WORD ?
        {24'hc35a7e,stamp,sequence,~stamp,8'ha6} : data_in;
endmodule

module frame_tag_rx #(
    parameter integer CLK_HZ=75000000,
    parameter integer TAG_Y=2
)(
    input wire clk,rst_n,de,
    input wire [11:0] x,y,
    input wire [23:0] rgb,
    output reg [31:0] time_gray,
    output reg [31:0] latency_us,
    output wire alive,
    output reg tag_valid
);
    localparam integer US_TICKS=CLK_HZ/1000000;
    reg [15:0] prescale;
    reg [31:0] time_us,age,last_sequence;
    reg [119:0] pixels;
    reg seen;
    wire [127:0] packet={pixels,rgb[23:16]};
    wire [31:0] stamp=packet[103:72],sequence=packet[71:40];
    wire [31:0] elapsed=time_us-stamp;
    wire packet_ok=packet[127:104]==24'hc35a7e && packet[39:8]==~stamp &&
                   packet[7:0]==8'ha6 && elapsed<1000000;
    assign alive=seen && age<CLK_HZ/10;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            prescale<=0; time_us<=0; time_gray<=0; age<=CLK_HZ/10;
            last_sequence<=0; pixels<=0; seen<=0; latency_us<=0; tag_valid<=0;
        end else begin
            // tag_valid is an event for the current packet, not a sticky
            // level.  This prevents a frozen frame from looking fresh.
            tag_valid<=1'b0;
            if(prescale==US_TICKS-1) begin
                prescale<=0; time_us<=time_us+1'b1;
                time_gray<=((time_us+32'd1)>>1)^(time_us+32'd1);
            end else prescale<=prescale+1'b1;
            if(age<CLK_HZ/10) age<=age+1'b1;
            if(de && y==TAG_Y && x<5) pixels<={pixels[95:0],rgb};
            if(de && y==TAG_Y && x==5) begin
                tag_valid<=packet_ok;
                if(packet_ok) begin
                    latency_us<=elapsed;
                    if(!seen || sequence!=last_sequence) begin
                        seen<=1; age<=0; last_sequence<=sequence;
                    end
                end
            end
        end
    end
endmodule
