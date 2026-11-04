module vision_core #(
    parameter integer WIDTH = 1280,
    parameter integer HEIGHT = 720,
    parameter integer CELL_SHIFT = 5,
    parameter integer MIN_CELLS = 4
)(
    input wire clk, rst_n, de, frame_tick,
    input wire [11:0] x, y,
    input wire [23:0] rgb,
    input wire [1:0] color,
    input wire moving, source_alive,
    output wire color_hit,
    output reg target_valid,
    output reg [11:0] left, right, top, bottom, cx, cy,
    output reg [12:0] area,
    output reg [1:0] shape,
    output reg motion_valid,
    output reg [11:0] motion_left, motion_right, motion_top, motion_bottom,
    output reg busy, overrun,
    output reg [31:0] analysis_cycles
);
    localparam integer GW=(WIDTH+(1<<CELL_SHIFT)-1)>>CELL_SHIFT;
    localparam integer GH=(HEIGHT+(1<<CELL_SHIFT)-1)>>CELL_SHIFT;
    localparam integer N=GW*GH;
    localparam integer SAMPLE=(1<<CELL_SHIFT)/4;
    localparam [4:0] IDLE=0, SCAN_REQ=1, SCAN_WAIT=2, SCAN_TEST=3,
        POP_REQ=4, POP_WAIT=5, POP_USE=6, NEIGHBOR=7, N_WAIT=8,
        N_TEST=9, NEXT_N=10, COMPONENT=11, ADVANCE=12, FINISH=13;
    reg mask [0:1023];
    reg [7:0] previous [0:1023];
    reg [19:0] queue [0:1023];
    reg mask_q;
    reg [7:0] prev_q;
    reg [19:0] queue_q;
    reg [9:0] read_addr;
    reg [10:0] qhead, qtail;
    reg [4:0] state;
    reg [9:0] scan, node, neighbor_addr;
    reg [4:0] scan_y, node_y, ymin, ymax, best_ymin, best_ymax;
    reg [5:0] scan_x, node_x, xmin, xmax, best_xmin, best_xmax;
    reg [1:0] direction;
    reg [12:0] count, best_count;
    reg [31:0] cycles;
    reg previous_ready;
    reg [1:0] old_color;
    reg [11:0] ml, mr, mt, mb;
    reg [12:0] mc;
    reg [9:0] samples;
    reg [1:0] good_frames;
    reg [9:0] pending_addr;
    reg [11:0] pending_x, pending_y;
    reg [7:0] pending_gray;
    reg pending_sample;
    wire [8:0] r={1'b0,rgb[23:16]}, g={1'b0,rgb[15:8]}, b={1'b0,rgb[7:0]};
    wire [9:0] luma_sum={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
    wire [7:0] gray=luma_sum[9:2];
    assign color_hit = color==0 ? (r>100 && r>g+40 && r>b+40) :
                       color==1 ? (g>90 && g>r+30 && g>b+25) :
                                  (b>100 && b>r+35 && b>g+25);
    wire sample = de && x[CELL_SHIFT-1:0]==SAMPLE && y[CELL_SHIFT-1:0]==SAMPLE;
    wire [9:0] sample_addr=(y>>CELL_SHIFT)*GW+(x>>CELL_SHIFT);
    wire end_frame=de && x==WIDTH-1 && y==HEIGHT-1;
    wire [7:0] diff=prev_q>pending_gray ? prev_q-pending_gray : pending_gray-prev_q;
    wire neighbor_ok = direction==0 ? node_x>0 : direction==1 ? node_x<GW-1 :
                       direction==2 ? node_y>0 : node_y<GH-1;
    wire [5:0] neighbor_x=direction==0 ? node_x-1'b1 : direction==1 ? node_x+1'b1 : node_x;
    wire [4:0] neighbor_y=direction==2 ? node_y-1'b1 : direction==3 ? node_y+1'b1 : node_y;
    wire [9:0] neighbor_index=direction==0 ? node-1'b1 : direction==1 ? node+1'b1 :
                              direction==2 ? node-GW : node+GW;
    wire [6:0] bw={1'b0,best_xmax}-{1'b0,best_xmin}+1'b1;
    wire [5:0] bh={1'b0,best_ymax}-{1'b0,best_ymin}+1'b1;
    wire [12:0] box_area=bw*bh;
    wire geometry_ok=best_count>=MIN_CELLS && best_count<N/2 &&
                     bw>=2 && bh>=2 && best_count*4>=box_area;
    wire [11:0] bx1=(best_xmin<<CELL_SHIFT), by1=(best_ymin<<CELL_SHIFT);
    wire [11:0] bx2raw=((best_xmax+12'd1)<<CELL_SHIFT)-1'b1;
    wire [11:0] by2raw=((best_ymax+12'd1)<<CELL_SHIFT)-1'b1;
    wire [11:0] bx2=bx2raw>=WIDTH ? WIDTH-1 : bx2raw;
    wire [11:0] by2=by2raw>=HEIGHT ? HEIGHT-1 : by2raw;
    wire [12:0] center_x={1'b0,bx1}+{1'b0,bx2};
    wire [12:0] center_y={1'b0,by1}+{1'b0,by2};

    // Synchronous memories; no reset loop on RAM contents. All mask cells must be captured before scanning.
    always @(posedge clk) begin
        mask_q<=mask[read_addr];
        queue_q<=queue[qhead[9:0]];
        if(sample) begin
            prev_q<=previous[sample_addr]; previous[sample_addr]<=gray;
        end
        if(sample && !busy) mask[sample_addr]<=color_hit;
        else if(state==SCAN_TEST && mask_q) mask[scan]<=0;
        else if(state==N_TEST && mask_q) mask[neighbor_addr]<=0;
        if(state==SCAN_TEST && mask_q) queue[0]<={scan_y,scan_x,scan[8:0]};
        // Queue packs coordinates only; address is reconstructed on pop.
        if(state==N_TEST && mask_q) queue[qtail[9:0]]<={neighbor_y,neighbor_x,9'd0};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; busy<=0; overrun<=0; cycles<=0; analysis_cycles<=0;
            scan<=0; scan_x<=0; scan_y<=0; read_addr<=0;
            qhead<=0; qtail<=0; node<=0; node_x<=0; node_y<=0; direction<=0; neighbor_addr<=0;
            count<=0; best_count<=0; xmin<=0; xmax<=0; ymin<=0; ymax<=0;
            best_xmin<=0; best_xmax<=0; best_ymin<=0; best_ymax<=0;
            target_valid<=0; left<=0; right<=0; top<=0; bottom<=0; cx<=WIDTH/2; cy<=HEIGHT/2;
            area<=0; shape<=0; previous_ready<=0; old_color<=0; good_frames<=0;
            motion_valid<=0; motion_left<=0; motion_right<=0; motion_top<=0; motion_bottom<=0;
            ml<=WIDTH-1; mr<=0; mt<=HEIGHT-1; mb<=0; mc<=0; samples<=0;
            pending_sample<=0; pending_addr<=0; pending_x<=0; pending_y<=0; pending_gray<=0;
        end else begin
            pending_sample<=sample;
            if(sample) begin
                pending_addr<=sample_addr; pending_gray<=gray; pending_x<=x; pending_y<=y;
                if(!busy) samples<=samples+1'b1;
                else overrun<=1;
            end
            if(pending_sample && previous_ready && !moving && diff>28) begin
                mc<=mc+1'b1;
                if(pending_x<ml) ml<=pending_x; if(pending_x>mr) mr<=pending_x;
                if(pending_y<mt) mt<=pending_y; if(pending_y>mb) mb<=pending_y;
            end
            if(frame_tick) begin
                old_color<=color;
                if(old_color!=color || !source_alive) begin target_valid<=0; good_frames<=0; end
            end
            if(busy) cycles<=cycles+1'b1;
            case(state)
                IDLE: if(end_frame) begin
                    motion_valid<=previous_ready && !moving && mc>=MIN_CELLS && mc<N/3;
                    motion_left<=ml; motion_right<=mr; motion_top<=mt; motion_bottom<=mb;
                    ml<=WIDTH-1; mr<=0; mt<=HEIGHT-1; mb<=0; mc<=0;
                    previous_ready<=samples==N;
                    samples<=0;
                    if(samples==N && source_alive) begin
                        busy<=1; cycles<=0; scan<=0; scan_x<=0; scan_y<=0;
                        best_count<=0; state<=SCAN_REQ;
                    end else begin target_valid<=0; good_frames<=0; end
                end
                SCAN_REQ: begin read_addr<=scan; state<=SCAN_WAIT; end
                SCAN_WAIT: state<=SCAN_TEST;
                SCAN_TEST: if(mask_q) begin
                    qhead<=0; qtail<=1; count<=0;
                    xmin<=scan_x; xmax<=scan_x; ymin<=scan_y; ymax<=scan_y;
                    state<=POP_REQ;
                end else state<=ADVANCE;
                POP_REQ: state<=POP_WAIT;
                POP_WAIT: state<=POP_USE;
                POP_USE: begin
                    node_x<=queue_q[14:9]; node_y<=queue_q[19:15];
                    node<=queue_q[19:15]*GW+queue_q[14:9];
                    qhead<=qhead+1'b1; count<=count+1'b1;
                    if(queue_q[14:9]<xmin) xmin<=queue_q[14:9];
                    if(queue_q[14:9]>xmax) xmax<=queue_q[14:9];
                    if(queue_q[19:15]<ymin) ymin<=queue_q[19:15];
                    if(queue_q[19:15]>ymax) ymax<=queue_q[19:15];
                    direction<=0; state<=NEIGHBOR;
                end
                NEIGHBOR: if(neighbor_ok) begin
                    read_addr<=neighbor_index; neighbor_addr<=neighbor_index; state<=N_WAIT;
                end else state<=NEXT_N;
                N_WAIT: state<=N_TEST;
                N_TEST: begin
                    if(mask_q) qtail<=qtail+1'b1;
                    state<=NEXT_N;
                end
                NEXT_N: if(direction==3) begin
                    if(qhead==qtail) state<=COMPONENT; else state<=POP_REQ;
                end else begin direction<=direction+1'b1; state<=NEIGHBOR; end
                COMPONENT: begin
                    if(count>best_count) begin
                        best_count<=count; best_xmin<=xmin; best_xmax<=xmax;
                        best_ymin<=ymin; best_ymax<=ymax;
                    end
                    state<=ADVANCE;
                end
                ADVANCE: if(scan==N-1) state<=FINISH;
                else begin
                    scan<=scan+1'b1;
                    if(scan_x==GW-1) begin scan_x<=0; scan_y<=scan_y+1'b1; end
                    else scan_x<=scan_x+1'b1;
                    state<=SCAN_REQ;
                end
                FINISH: begin
                    state<=IDLE; busy<=0; analysis_cycles<=cycles;
                    area<=best_count;
                    if(geometry_ok && source_alive) begin
                        if(good_frames!=3) good_frames<=good_frames+1'b1;
                        target_valid<=good_frames>=1;
                        left<=bx1; right<=bx2; top<=by1; bottom<=by2;
                        cx<=center_x[12:1]; cy<=center_y[12:1];
                        if(bw>bh*2 || bh>bw*2) shape<=3;
                        else if(best_count*8>=box_area*7) shape<=1;
                        else shape<=2;
                    end else begin target_valid<=0; good_frames<=0; shape<=0; end
                end
                default: begin state<=IDLE; busy<=0; target_valid<=0; end
            endcase
        end
    end
endmodule
