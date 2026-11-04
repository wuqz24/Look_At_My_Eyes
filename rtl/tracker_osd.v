// Fixed English status layer. Character coordinates use powers of two so the
// OSD does not add general-purpose division or remainder hardware.
module tracker_osd (
    input wire clk,rst_n,frame_tick,
    input wire [11:0] x,y,cx,cy,
    input wire [2:0] mode,
    input wire [1:0] color,shape,
    input wire valid,armed,alive,moving,overrun,
    input wire [15:0] area,
    input wire [31:0] analysis_cycles,
    input wire [31:0] latency_us,
    input wire tag_valid,
    input wire red_valid,green_valid,blue_valid,yellow_valid,
    input wire [11:0] red_cx,red_cy,green_cx,green_cy,blue_cx,blue_cy,yellow_cx,yellow_cy,
    input wire [12:0] red_area,green_area,blue_area,yellow_area,
    input wire [1:0] red_shape,green_shape,blue_shape,yellow_shape,
    input wire [7:0] red_confidence,green_confidence,blue_confidence,yellow_confidence,
    input wire follow_enable,
    input wire limit,
    input wire [9:0] red_hits,
    input wire [9:0] blue_hits,
    output wire text_hit
);
    localparam integer X0=912;
    localparam integer Y0=220;
    localparam integer CELL=16;
    localparam integer PANEL_W=256;
    // There are 12 status rows, each 16 pixels high.  Keeping the active
    // region to those rows prevents the 4-bit line index from wrapping and
    // drawing a second copy below the intended status panel.
    localparam integer PANEL_H=192;
    reg [7:0] code;
    reg [7:0] bits;
    reg [3:0] glyph_row;
    reg [3:0] glyph_col;
    reg active;
    reg [3:0] line;
    reg [3:0] col;
    reg [7:0] hex0;
    reg [11:0] value12;
    reg [11:0] local_x,local_y;



    // ASCII 5x7 glyphs, enlarged to 2x2 pixels. Unknown characters are blank.
    function [7:0] ascii5;
        input [7:0] c;
        input [2:0] r;
        begin
            ascii5=0;
            case(c)
              8'h20: ascii5=0;
              8'h30: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h13;3:ascii5=8'h15;4:ascii5=8'h19;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h31: case(r)0:ascii5=8'h04;1:ascii5=8'h0c;2:ascii5=8'h04;3:ascii5=8'h04;4:ascii5=8'h04;5:ascii5=8'h04;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h32: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h01;3:ascii5=8'h02;4:ascii5=8'h04;5:ascii5=8'h08;6:ascii5=8'h1f;default:ascii5=0;endcase
              8'h33: case(r)0:ascii5=8'h1e;1:ascii5=8'h01;2:ascii5=8'h01;3:ascii5=8'h0e;4:ascii5=8'h01;5:ascii5=8'h01;6:ascii5=8'h1e;default:ascii5=0;endcase
              8'h34: case(r)0:ascii5=8'h02;1:ascii5=8'h06;2:ascii5=8'h0a;3:ascii5=8'h12;4:ascii5=8'h1f;5:ascii5=8'h02;6:ascii5=8'h02;default:ascii5=0;endcase
              8'h35: case(r)0:ascii5=8'h1f;1:ascii5=8'h10;2:ascii5=8'h1e;3:ascii5=8'h01;4:ascii5=8'h01;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h36: case(r)0:ascii5=8'h06;1:ascii5=8'h08;2:ascii5=8'h10;3:ascii5=8'h1e;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h37: case(r)0:ascii5=8'h1f;1:ascii5=8'h01;2:ascii5=8'h02;3:ascii5=8'h04;4:ascii5=8'h08;5:ascii5=8'h08;6:ascii5=8'h08;default:ascii5=0;endcase
              8'h38: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h0e;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h39: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h0f;4:ascii5=8'h01;5:ascii5=8'h02;6:ascii5=8'h0c;default:ascii5=0;endcase
              8'h41: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h1f;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h42: case(r)0:ascii5=8'h1e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h1e;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h1e;default:ascii5=0;endcase
              8'h43: case(r)0:ascii5=8'h0f;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h10;4:ascii5=8'h10;5:ascii5=8'h10;6:ascii5=8'h0f;default:ascii5=0;endcase
              8'h44: case(r)0:ascii5=8'h1e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h11;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h1e;default:ascii5=0;endcase
              8'h45: case(r)0:ascii5=8'h1f;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h1e;4:ascii5=8'h10;5:ascii5=8'h10;6:ascii5=8'h1f;default:ascii5=0;endcase
              8'h46: case(r)0:ascii5=8'h1f;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h1e;4:ascii5=8'h10;5:ascii5=8'h10;6:ascii5=8'h10;default:ascii5=0;endcase
              8'h47: case(r)0:ascii5=8'h0f;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h17;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h0f;default:ascii5=0;endcase
              8'h48: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h1f;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h49: case(r)0:ascii5=8'h1f;1:ascii5=8'h04;2:ascii5=8'h04;3:ascii5=8'h04;4:ascii5=8'h04;5:ascii5=8'h04;6:ascii5=8'h1f;default:ascii5=0;endcase
              8'h4a: case(r)0:ascii5=8'h07;1:ascii5=8'h02;2:ascii5=8'h02;3:ascii5=8'h02;4:ascii5=8'h12;5:ascii5=8'h12;6:ascii5=8'h0c;default:ascii5=0;endcase
              8'h4b: case(r)0:ascii5=8'h11;1:ascii5=8'h12;2:ascii5=8'h14;3:ascii5=8'h18;4:ascii5=8'h14;5:ascii5=8'h12;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h4c: case(r)0:ascii5=8'h10;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h10;4:ascii5=8'h10;5:ascii5=8'h10;6:ascii5=8'h1f;default:ascii5=0;endcase
              8'h4d: case(r)0:ascii5=8'h11;1:ascii5=8'h1b;2:ascii5=8'h15;3:ascii5=8'h15;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h4e: case(r)0:ascii5=8'h11;1:ascii5=8'h19;2:ascii5=8'h15;3:ascii5=8'h13;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h4f: case(r)0:ascii5=8'h0e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h11;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h50: case(r)0:ascii5=8'h1e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h1e;4:ascii5=8'h10;5:ascii5=8'h10;6:ascii5=8'h10;default:ascii5=0;endcase
              8'h52: case(r)0:ascii5=8'h1e;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h1e;4:ascii5=8'h14;5:ascii5=8'h12;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h53: case(r)0:ascii5=8'h0f;1:ascii5=8'h10;2:ascii5=8'h10;3:ascii5=8'h0e;4:ascii5=8'h01;5:ascii5=8'h01;6:ascii5=8'h1e;default:ascii5=0;endcase
              8'h54: case(r)0:ascii5=8'h1f;1:ascii5=8'h04;2:ascii5=8'h04;3:ascii5=8'h04;4:ascii5=8'h04;5:ascii5=8'h04;6:ascii5=8'h04;default:ascii5=0;endcase
              8'h55: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h11;4:ascii5=8'h11;5:ascii5=8'h11;6:ascii5=8'h0e;default:ascii5=0;endcase
              8'h56: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h11;4:ascii5=8'h0a;5:ascii5=8'h0a;6:ascii5=8'h04;default:ascii5=0;endcase
              8'h57: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h11;3:ascii5=8'h15;4:ascii5=8'h15;5:ascii5=8'h1b;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h58: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h0a;3:ascii5=8'h04;4:ascii5=8'h0a;5:ascii5=8'h11;6:ascii5=8'h11;default:ascii5=0;endcase
              8'h59: case(r)0:ascii5=8'h11;1:ascii5=8'h11;2:ascii5=8'h0a;3:ascii5=8'h04;4:ascii5=8'h04;5:ascii5=8'h04;6:ascii5=8'h04;default:ascii5=0;endcase
              8'h5a: case(r)0:ascii5=8'h1f;1:ascii5=8'h01;2:ascii5=8'h02;3:ascii5=8'h04;4:ascii5=8'h08;5:ascii5=8'h10;6:ascii5=8'h1f;default:ascii5=0;endcase
              8'h3a: case(r)2:ascii5=8'h04;4:ascii5=8'h04;default:ascii5=0;endcase
              8'h2f: case(r)0:ascii5=8'h01;1:ascii5=8'h02;2:ascii5=8'h02;3:ascii5=8'h04;4:ascii5=8'h08;5:ascii5=8'h08;6:ascii5=8'h10;default:ascii5=0;endcase
              8'h2d: case(r)3:ascii5=8'h1f;default:ascii5=0;endcase
              default: ascii5=0;
            endcase
        end
    endfunction

    reg [11:0] cx_latched, cy_latched;
    reg valid_latched;
    reg [1:0] color_latched, shape_latched;
    reg [3:0] cx_k, cx_h, cx_t, cx_o, cy_k, cy_h, cy_t, cy_o;
    reg [3:0] area_tt, area_th, area_h, area_t, area_o;
    reg [15:0] area_work;
    reg [9:0] hit_work;
    reg [3:0] rh_h, rh_t, rh_o, bh_h, bh_t, bh_o;
    reg [31:0] latency_latched;
    reg [3:0] lat_h, lat_t, lat_o, lat_u;
    // 2026-11-01: tag_valid is a single-clock event; latch it so the TAG line
    // can show OK instead of always WAIT.
    reg tag_sticky, tag_latched;

    function [7:0] dec_digit;
        input [3:0] n;
        begin dec_digit=8'd48+n; end
    endfunction
    function [7:0] none_char;
        input [3:0] idx;
        begin
            case(idx)
                0:none_char="N"; 1:none_char="O"; 2:none_char="N"; 3:none_char="E";
                default:none_char=8'h20;
            endcase
        end
    endfunction
    function [7:0] color_char;
        input [1:0] value;
        input [3:0] idx;
        begin
            color_char=8'h20;
            case(value)
                2'd0: case(idx) 0:color_char="R"; 1:color_char="E"; 2:color_char="D"; default:color_char=8'h20; endcase
                2'd1: case(idx) 0:color_char="G"; 1:color_char="R"; 2:color_char="E"; 3:color_char="E"; 4:color_char="N"; default:color_char=8'h20; endcase
                2'd2: case(idx) 0:color_char="B"; 1:color_char="L"; 2:color_char="U"; 3:color_char="E"; default:color_char=8'h20; endcase
                2'd3: case(idx) 0:color_char="Y"; 1:color_char="E"; 2:color_char="L"; 3:color_char="L"; 4:color_char="O"; 5:color_char="W"; default:color_char=8'h20; endcase
            endcase
        end
    endfunction
    function [7:0] shape_char;
        input [1:0] value;
        input [3:0] idx;
        begin
            shape_char=8'h20;
            case(value)
                2'd1: case(idx) 0:shape_char="C"; 1:shape_char="I"; 2:shape_char="R"; 3:shape_char="C"; 4:shape_char="L"; 5:shape_char="E"; default:shape_char=8'h20; endcase
                2'd2: case(idx) 0:shape_char="R"; 1:shape_char="E"; 2:shape_char="C"; 3:shape_char="T"; 4:shape_char="A"; 5:shape_char="N"; 6:shape_char="G"; 7:shape_char="L"; 8:shape_char="E"; default:shape_char=8'h20; endcase
                2'd3: case(idx) 0:shape_char="O"; 1:shape_char="T"; 2:shape_char="H"; 3:shape_char="E"; 4:shape_char="R"; default:shape_char=8'h20; endcase
                default: shape_char=none_char(idx);
            endcase
        end
    endfunction
    task automatic split12;
        input [11:0] v;
        output [3:0] k,h,t,o;
        reg [11:0] q;
        begin
            k=0; h=0; t=0; o=0; q=v;
            if(q>=1000) begin k=1; q=q-1000; end
            if(q>=900) begin h=9; q=q-900; end
            else if(q>=800) begin h=8; q=q-800; end
            else if(q>=700) begin h=7; q=q-700; end
            else if(q>=600) begin h=6; q=q-600; end
            else if(q>=500) begin h=5; q=q-500; end
            else if(q>=400) begin h=4; q=q-400; end
            else if(q>=300) begin h=3; q=q-300; end
            else if(q>=200) begin h=2; q=q-200; end
            else if(q>=100) begin h=1; q=q-100; end
            if(q>=90) begin t=9; q=q-90; end
            else if(q>=80) begin t=8; q=q-80; end
            else if(q>=70) begin t=7; q=q-70; end
            else if(q>=60) begin t=6; q=q-60; end
            else if(q>=50) begin t=5; q=q-50; end
            else if(q>=40) begin t=4; q=q-40; end
            else if(q>=30) begin t=3; q=q-30; end
            else if(q>=20) begin t=2; q=q-20; end
            else if(q>=10) begin t=1; q=q-10; end
            o=q[3:0];
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cx_latched<=0; cy_latched<=0; valid_latched<=0; latency_latched<=0;
            color_latched<=0; shape_latched<=0;
            cx_k<=0;cx_h<=0;cx_t<=0;cx_o<=0;cy_k<=0;cy_h<=0;cy_t<=0;cy_o<=0;
            area_tt<=0;area_th<=0;area_h<=0;area_t<=0;area_o<=0;
            rh_h<=0;rh_t<=0;rh_o<=0;bh_h<=0;bh_t<=0;bh_o<=0;
            lat_h<=0;lat_t<=0;lat_o<=0;lat_u<=0;
        end else if(frame_tick) begin
            cx_latched<=cx; cy_latched<=cy; valid_latched<=valid; latency_latched<=latency_us;
            color_latched<=color; shape_latched<=shape;
            split12(cx,cx_k,cx_h,cx_t,cx_o); split12(cy,cy_k,cy_h,cy_t,cy_o);
            // Five decimal digits: the published area is 16 bit now, so a large
            // target keeps changing with distance instead of saturating at 8191.
            area_work=area;
            area_tt<=0; area_th<=0; area_h<=0; area_t<=0; area_o<=0;
            if(area_work>=10000) begin area_tt<=area_work/10000; area_work=area_work%10000; end
            if(area_work>=1000) begin area_th<=area_work/1000; area_work=area_work%1000; end
            if(area_work>=100) begin area_h<=area_work/100; area_work=area_work%100; end
            if(area_work>=10) begin area_t<=area_work/10; area_work=area_work%10; end
            area_o<=area_work[3:0];
            // Colour hit counters for the HITS row (diagnostic: does the colour
            // test fire at all on the object being held?).
            hit_work=red_hits;
            rh_h<=0; rh_t<=0; rh_o<=0;
            if(hit_work>=100) begin rh_h<=hit_work/100; hit_work=hit_work%100; end
            if(hit_work>=10) begin rh_t<=hit_work/10; hit_work=hit_work%10; end
            rh_o<=hit_work[3:0];
            hit_work=blue_hits;
            bh_h<=0; bh_t<=0; bh_o<=0;
            if(hit_work>=100) begin bh_h<=hit_work/100; hit_work=hit_work%100; end
            if(hit_work>=10) begin bh_t<=hit_work/10; hit_work=hit_work%10; end
            bh_o<=hit_work[3:0];
            if(latency_us>=1000) lat_h<=1; else lat_h<=0;
            if(latency_us>=100) lat_t<= (latency_us/100)%10; else lat_t<=0;
            if(latency_us>=10) lat_o<= (latency_us/10)%10; else lat_o<=0;
            lat_u<=latency_us[3:0];
        end
    end

    // Sticky TAG validity: set by the one-cycle tag_valid pulse, captured into
    // tag_latched at the frame boundary that ends the frame it belongs to.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tag_sticky<=1'b0; tag_latched<=1'b0;
        end else begin
            if(tag_valid) tag_sticky<=1'b1;
            if(frame_tick) begin
                tag_latched<=tag_sticky;
                tag_sticky<=1'b0;
            end
        end
    end

    function [7:0] text_char;
        input [4:0] ln;
        input [4:0] p;
        begin
            text_char=8'h20;
            case(ln)
              0: case(p)0:text_char="D";1:text_char="E";2:text_char="T";3:text_char="E";4:text_char="C";5:text_char="T";6:text_char="I";7:text_char="O";8:text_char="N";default:text_char=8'h20;endcase
              1: case(p)0:text_char="O";1:text_char="B";2:text_char="J";3:text_char="E";4:text_char="C";5:text_char="T";7:text_char=valid_latched?"F":"N";8:text_char=valid_latched?"O":"O";9:text_char=valid_latched?"U":"N";10:text_char=valid_latched?"N":"E";11:text_char=valid_latched?"D":8'h20;default:text_char=8'h20;endcase
              2: case(p)0:text_char="C";1:text_char="O";2:text_char="L";3:text_char="O";4:text_char="R";7,8,9,10,11,12,13:text_char=valid_latched?color_char(color_latched,p-7):none_char(p-7);default:text_char=8'h20;endcase
              3: case(p)0:text_char="S";1:text_char="H";2:text_char="A";3:text_char="P";4:text_char="E";7,8,9,10,11,12,13,14,15:text_char=valid_latched?shape_char(shape_latched,p-7):none_char(p-7);default:text_char=8'h20;endcase
              4: case(p)0:text_char="P";1:text_char="O";2:text_char="S";3:text_char="X";7:text_char=valid_latched?dec_digit(cx_k):"0";8:text_char=valid_latched?dec_digit(cx_h):"0";9:text_char=valid_latched?dec_digit(cx_t):"0";10:text_char=valid_latched?dec_digit(cx_o):"0";default:text_char=8'h20;endcase
              5: case(p)0:text_char="P";1:text_char="O";2:text_char="S";3:text_char="Y";7:text_char=valid_latched?dec_digit(cy_k):"0";8:text_char=valid_latched?dec_digit(cy_h):"0";9:text_char=valid_latched?dec_digit(cy_t):"0";10:text_char=valid_latched?dec_digit(cy_o):"0";default:text_char=8'h20;endcase
              6: case(p)0:text_char="A";1:text_char="R";2:text_char="E";3:text_char="A";7:text_char=valid_latched?dec_digit(area_tt):"0";8:text_char=valid_latched?dec_digit(area_th):"0";9:text_char=valid_latched?dec_digit(area_h):"0";10:text_char=valid_latched?dec_digit(area_t):"0";11:text_char=valid_latched?dec_digit(area_o):"0";default:text_char=8'h20;endcase
              7: case(p)0:text_char="T";1:text_char="R";2:text_char="A";3:text_char="C";4:text_char="K";7:text_char=follow_enable?(limit?"L":"T"):"O";8:text_char=follow_enable?(limit?"I":"R"):"F";9:text_char=follow_enable?(limit?"M":"A"):"F";10:text_char=follow_enable?(limit?"I":"C"):8'h20;11:text_char=follow_enable?(limit?"T":"K"):8'h20;default:text_char=8'h20;endcase
              8: case(p)0:text_char="V";1:text_char="I";2:text_char="D";3:text_char="E";4:text_char="O";7:text_char=alive?"L":"L";8:text_char=alive?"I":"O";9:text_char=alive?"V":"S";10:text_char=alive?"E":"T";default:text_char=8'h20;endcase
              9: case(p)0:text_char="A";1:text_char="R";2:text_char="M";3:text_char="E";4:text_char="D";7:text_char=armed?"Y":"N";8:text_char=armed?"E":"O";9:text_char=armed?"S":8'h20;default:text_char=8'h20;endcase
              10: case(p)0:text_char="H";1:text_char="I";2:text_char="T";3:text_char="S";7:text_char="R";8:text_char=dec_digit(rh_h);9:text_char=dec_digit(rh_t);10:text_char=dec_digit(rh_o);11:text_char=8'h20;12:text_char="B";13:text_char=dec_digit(bh_h);14:text_char=dec_digit(bh_t);15:text_char=dec_digit(bh_o);default:text_char=8'h20;endcase
              11: case(p)0:text_char="T";1:text_char="A";2:text_char="G";7:text_char=tag_latched?"O":"W";8:text_char=tag_latched?"K":"A";9:text_char=tag_latched?8'h20:"I";10:text_char=tag_latched?8'h20:"T";default:text_char=8'h20;endcase
              default:text_char=8'h20;
            endcase
        end
    endfunction    always @* begin
        active=(x>=X0 && x<X0+PANEL_W && y>=Y0 && y<Y0+PANEL_H);
        local_x=active ? x-X0 : 0;
        local_y=active ? y-Y0 : 0;
        line=local_y>>4; col=local_x>>4;
        code=active ? text_char(line,col) : 8'h20;
        glyph_row=local_y[3:0]; glyph_col=local_x[3:0];
        bits=ascii5(code,glyph_row>>1);
    end
    assign text_hit=active && bits[7-(glyph_col>>1)];
endmodule
