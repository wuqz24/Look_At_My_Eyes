


module video_out (
    input wire        I_rst_n,
    input wire        I_ddr_rst_n,
    input wire        I_dsi_rst_n,

    input wire        I_ddr_clk,
    output wire       O_video_out_rd_busy,  
    input wire        I_video_in_wr_busy,   
    input wire[1:0]   I_video_out_rp,
    output wire       O_ddr_user_rd_en,
    output reg[24:0]  O_ddr_user_addr,
    input wire        I_ddr_user_ready,
    input wire        I_ddr_user_rd_valid,
    input wire[127:0] I_ddr_user_rd_data,

    input wire        I_dsi_clk,
    input wire        I_video_vsync,
    input wire        I_video_rd_en,  
    output reg[23:0]  O_vdieo_data
);

    reg         S_fifo_rst;     
    reg[7:0]    S_fifo_rst_cnt;
    wire[8:0]   S_fifo_wr_num;       
    wire        S_fifo_rd_en;        
    wire[127:0] S_fifo_rd_data;      
    wire[8:0]   S_fifo_rd_num;
    reg         S_video_vsync_1d;
    reg         S_video_vsync_2d;
    reg         S_video_vsync_3d;
    reg         S_video_vsync_dsi_1d;
    reg         S_video_vsync_dsi_2d;
    wire        S_video_frame_start;   
    wire        S_ddr_rd_trig;       
    reg         S_ddr_rd_valid;      
    reg[9:0]    S_ddr_rd_cnt;        
    reg[9:0]    S_ddr_rd_pending_cnt;
    reg[3:0]    S_fifo_rd_cnt;       
    reg         S_video_rd_en_1d;
    reg[3:0]    S_fifo_rd_cnt_1d;     
    reg[127:0]  S_fifo_rd_data_1d;    
	reg         S_fifo_word0_valid;
	reg         S_fifo_word1_valid;
	reg         S_fifo_word2_valid;
    reg[1:0]    S_fifo_rd_slot_1d;
    reg         S_frame_display_valid;
    reg         S_frame_decision_made;
    wire        S_fifo_current_valid;
    wire        S_frame_display_enable;
	wire        S_fifo_word0_active;
	wire        S_fifo_word1_active;
	wire        S_fifo_word2_active;
    wire        S_fifo_emtpy;     
    wire        S_ddr_reset_n;
    wire        S_dsi_reset_n;
    wire        S_fifo_reset;

    assign S_ddr_reset_n = I_rst_n && I_ddr_rst_n;
    assign S_dsi_reset_n = I_rst_n && I_dsi_rst_n;
    // The generated FIFO has one asynchronous reset for both clock ports.
    // Assert it from either domain so a display-domain restart cannot expose
    // words written before the restart.
    assign S_fifo_reset = S_fifo_rst || !S_ddr_reset_n || !S_dsi_reset_n;



    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    always @(posedge I_dsi_clk or negedge S_dsi_reset_n) begin
        if(!S_dsi_reset_n) begin
            S_video_vsync_dsi_1d <= 1'b0;
            S_video_vsync_dsi_2d <= 1'b0;
        end else begin
            S_video_vsync_dsi_1d <= I_video_vsync;
            S_video_vsync_dsi_2d <= S_video_vsync_dsi_1d;
        end
    end

    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_vsync_3d <= 1'b0;
        end else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
        end
    end

    assign S_video_frame_start = ~S_video_vsync_3d & S_video_vsync_2d;


    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            S_fifo_rst <= 1'b1;
        else
            if(S_video_frame_start)
                S_fifo_rst <= 1'b1;
            else if((S_fifo_rst_cnt >= 'd10) && (S_ddr_rd_pending_cnt == 'd0))
                S_fifo_rst <= 1'b0;
            else
                S_fifo_rst <= S_fifo_rst;
    end


    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            S_fifo_rst_cnt <= 8'd0;
        else if(S_fifo_rst)
            if(S_fifo_rst_cnt < 'd10)
                S_fifo_rst_cnt <= S_fifo_rst_cnt + 'd1;
            else
                S_fifo_rst_cnt <= S_fifo_rst_cnt;
        else
            S_fifo_rst_cnt <= 'd0;
    end

    // DDR read responses are untagged. Keep the frame FIFO in reset until all
    // requests issued before the frame boundary have returned and been
    // discarded, otherwise a late old-frame word can seed the new frame.
    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            S_ddr_rd_pending_cnt <= 10'd0;
        else
            case ({O_ddr_user_rd_en, I_ddr_user_rd_valid})
                2'b10: S_ddr_rd_pending_cnt <= S_ddr_rd_pending_cnt + 10'd1;
                2'b01: if(S_ddr_rd_pending_cnt != 10'd0)
                           S_ddr_rd_pending_cnt <= S_ddr_rd_pending_cnt - 10'd1;
                       else
                           S_ddr_rd_pending_cnt <= 10'd0;
                default: S_ddr_rd_pending_cnt <= S_ddr_rd_pending_cnt;
            endcase
    end

    /*
        这里需要注意fifo的剩余空间一定要大于将要写入的长度，因为ddr读出的时候会有至少40个时钟周期的延时，
        例如每次从ddr读出240个长度的数据，那么fifo的剩余空间最少要设为280，否则会引起fifo写满丢失数据。
    */
    assign S_ddr_rd_trig = (('d511 - S_fifo_wr_num) >= 'd300) && (!I_video_in_wr_busy) && (!S_ddr_rd_valid) && (!S_fifo_reset) && S_ddr_reset_n ? 1'b1 : 1'b0;

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次写入会引起fifo写满，丢失数据
    */
    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            S_ddr_rd_valid <= 1'b0;
        else if(S_video_frame_start)
            S_ddr_rd_valid <= 1'b0;
        else
			if(O_ddr_user_rd_en && S_ddr_rd_cnt == 'd239)
                S_ddr_rd_valid <= 1'b0;
            else if(S_ddr_rd_trig)
                S_ddr_rd_valid <= 1'b1;
            else
                S_ddr_rd_valid <= S_ddr_rd_valid;
    end

    assign O_ddr_user_rd_en = S_ddr_rd_valid & I_ddr_user_ready &
                               !S_fifo_reset & !S_video_frame_start & S_ddr_reset_n;

    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            S_ddr_rd_cnt <= 10'd0;
        else if(S_ddr_rd_valid)
            begin
                if(O_ddr_user_rd_en)
                    S_ddr_rd_cnt <= S_ddr_rd_cnt + 'd1;
                else
                    S_ddr_rd_cnt <= S_ddr_rd_cnt;
            end
        else    
            S_ddr_rd_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk or negedge S_ddr_reset_n) begin
        if(!S_ddr_reset_n)
            O_ddr_user_addr <= 'd0;
        else
            if(S_video_frame_start)
                begin
                    case(I_video_out_rp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
            else if(O_ddr_user_rd_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
    assign O_video_out_rd_busy = S_ddr_rd_trig | S_ddr_rd_valid;


    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_reset        ),   

        .clkw       ( I_ddr_clk           ),     
        .we         ( I_ddr_user_rd_valid ),
        .di         ( I_ddr_user_rd_data  ),
        .wrusedw    ( S_fifo_wr_num       ),
        .afull      (),
        .full_flag  (),
 
    .clkr       ( I_dsi_clk           ),     
        .re         ( S_fifo_rd_en        ), 
        .dout       ( S_fifo_rd_data      ),  
        .rdusedw    ( S_fifo_rd_num ), 
        .valid      ( S_fifo_current_valid ),  
        .empty_flag ( S_fifo_emtpy        ),
        .aempty     ()
    );

   // The generated FIFO is synchronous-read, so valid is asserted for the
   // word returned by the request from the previous read-clock edge. Keep
   // the response separate from the request; using S_fifo_rd_en here can
   // turn stale dout data into a visible pixel at a FIFO boundary.
   assign S_fifo_word0_active = S_fifo_word0_valid ||
                                (S_fifo_current_valid && S_fifo_rd_slot_1d == 2'd0);
   assign S_fifo_word1_active = S_fifo_word1_valid ||
                                (S_fifo_current_valid && S_fifo_rd_slot_1d == 2'd1);
   assign S_fifo_word2_active = S_fifo_word2_valid ||
                                (S_fifo_current_valid && S_fifo_rd_slot_1d == 2'd2);


   always @(posedge I_dsi_clk or negedge S_dsi_reset_n) begin
       if(!S_dsi_reset_n)
           S_fifo_rd_cnt <= 4'd0;
       else if(I_video_rd_en)
           S_fifo_rd_cnt <= S_fifo_rd_cnt + 'd1;
       else
           S_fifo_rd_cnt <= 'd0;
   end

   // Admit or reject a frame on its first active pixel only.  This prevents
   // a late DDR prefill from turning the rest of an already-started frame on.
   assign S_frame_display_enable = S_frame_display_valid ||
                                   (!S_frame_decision_made && I_video_rd_en &&
                                    !S_video_rd_en_1d && (S_fifo_rd_num >= 9'd240));
   assign S_fifo_rd_en = I_video_rd_en && !S_fifo_emtpy &&
                         S_frame_display_enable &&
                         ((S_fifo_rd_cnt == 'd0)  ||
                          (S_fifo_rd_cnt == 'd5)  ||
                          (S_fifo_rd_cnt == 'd10));

   always @(posedge I_dsi_clk or negedge S_dsi_reset_n) begin
       if(!S_dsi_reset_n) begin
           S_frame_display_valid <= 1'b0;
           S_frame_decision_made <= 1'b0;
           S_video_rd_en_1d  <= 1'b0;
           S_fifo_rd_cnt_1d  <= 4'd0;
           S_fifo_rd_data_1d <= 128'd0;
           S_fifo_word0_valid <= 1'b0;
           S_fifo_word1_valid <= 1'b0;
           S_fifo_word2_valid <= 1'b0;
           S_fifo_rd_slot_1d  <= 2'd0;
       end else begin
           if (S_video_vsync_dsi_1d != S_video_vsync_dsi_2d) begin
               S_frame_display_valid <= 1'b0;
               S_frame_decision_made <= 1'b0;
           end else if (!S_frame_decision_made && I_video_rd_en && !S_video_rd_en_1d) begin
               S_frame_display_valid <= (S_fifo_rd_num >= 9'd240);
               S_frame_decision_made <= 1'b1;
           end

           S_video_rd_en_1d  <= I_video_rd_en;
           S_fifo_rd_cnt_1d  <= S_fifo_rd_cnt;
           S_fifo_rd_data_1d <= S_fifo_rd_data;

           if(!I_video_rd_en) begin
               S_fifo_word0_valid <= 1'b0;
               S_fifo_word1_valid <= 1'b0;
               S_fifo_word2_valid <= 1'b0;
               S_fifo_rd_slot_1d  <= 2'd0;
           end else begin
               // Remember the slot belonging to this read request. The
               // FIFO response arrives one cycle later on this clock domain.
               if(S_fifo_rd_en) begin
                   case(S_fifo_rd_cnt)
                       4'd0: begin
                           S_fifo_rd_slot_1d  <= 2'd0;
                           S_fifo_word0_valid <= 1'b0;
                           S_fifo_word1_valid <= 1'b0;
                           S_fifo_word2_valid <= 1'b0;
                       end
                       4'd5: begin
                           S_fifo_rd_slot_1d  <= 2'd1;
                           S_fifo_word1_valid <= 1'b0;
                       end
                       4'd10: begin
                           S_fifo_rd_slot_1d  <= 2'd2;
                           S_fifo_word2_valid <= 1'b0;
                       end
                       default: begin
                           S_fifo_rd_slot_1d <= S_fifo_rd_slot_1d;
                       end
                   endcase
               end

               // Hold the response validity for the remaining pixels in its
               // five-pixel group. The direct valid term covers the first
               // pixel of the group before this register updates.
               if(S_fifo_current_valid) begin
                   case(S_fifo_rd_slot_1d)
                       2'd0: S_fifo_word0_valid <= 1'b1;
                       2'd1: S_fifo_word1_valid <= 1'b1;
                       2'd2: S_fifo_word2_valid <= 1'b1;
                       default: begin end
                   endcase
               end

               // Retire each five-pixel group after its last pixel. Without
               // this, an empty FIFO can keep replaying the previous frame's
               // word until the four-bit pixel counter wraps.
               if(S_fifo_rd_cnt_1d == 4'd5)
                   S_fifo_word0_valid <= 1'b0;
               if(S_fifo_rd_cnt_1d == 4'd10)
                   S_fifo_word1_valid <= 1'b0;
               if(S_fifo_rd_cnt_1d == 4'd15)
                   S_fifo_word2_valid <= 1'b0;
           end
       end
   end

   always @(posedge I_dsi_clk or negedge S_dsi_reset_n) begin
       if(!S_dsi_reset_n)
           O_vdieo_data <= 24'd0;
       else if(S_video_rd_en_1d && S_frame_display_enable)
           begin
               case(S_fifo_rd_cnt_1d)
                   'd0: O_vdieo_data  <= S_fifo_word0_active ? S_fifo_rd_data[127:104] : 24'd0;
                   'd1: O_vdieo_data  <= S_fifo_word0_active ? S_fifo_rd_data[103:80] : 24'd0;
                   'd2: O_vdieo_data  <= S_fifo_word0_active ? S_fifo_rd_data[79:56] : 24'd0;
                   'd3: O_vdieo_data  <= S_fifo_word0_active ? S_fifo_rd_data[55:32] : 24'd0;
                   'd4: O_vdieo_data  <= S_fifo_word0_active ? S_fifo_rd_data[31:8] : 24'd0;
                   'd5: O_vdieo_data  <= (S_fifo_word0_active && S_fifo_word1_active) ? {S_fifo_rd_data_1d[7:0],S_fifo_rd_data[127:112]} : 24'd0;
                   'd6: O_vdieo_data  <= S_fifo_word1_active ? S_fifo_rd_data[111:88] : 24'd0;
                   'd7: O_vdieo_data  <= S_fifo_word1_active ? S_fifo_rd_data[87:64] : 24'd0;
                   'd8: O_vdieo_data  <= S_fifo_word1_active ? S_fifo_rd_data[63:40] : 24'd0;
                   'd9: O_vdieo_data  <= S_fifo_word1_active ? S_fifo_rd_data[39:16] : 24'd0;
                   'd10: O_vdieo_data <= (S_fifo_word1_active && S_fifo_word2_active) ? {S_fifo_rd_data_1d[15:0],S_fifo_rd_data[127:120]} : 24'd0;
                   'd11: O_vdieo_data <= S_fifo_word2_active ? S_fifo_rd_data[119:96] : 24'd0;
                   'd12: O_vdieo_data <= S_fifo_word2_active ? S_fifo_rd_data[95:72] : 24'd0;
                   'd13: O_vdieo_data <= S_fifo_word2_active ? S_fifo_rd_data[71:48] : 24'd0;
                   'd14: O_vdieo_data <= S_fifo_word2_active ? S_fifo_rd_data[47:24] : 24'd0;
                   'd15: O_vdieo_data <= S_fifo_word2_active ? S_fifo_rd_data[23:0] : 24'd0;
               endcase
           end
       else
           O_vdieo_data <= 'd0;
   end

    
endmodule
