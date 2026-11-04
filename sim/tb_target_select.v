`timescale 1ns/1ps
module tb_target_select;
    reg rv=0,gv=0,bv=0,yv=0;
    reg [11:0] rx=0,ry=0,gx=0,gy=0,bx=0,by=0,yx=0,yy=0;
    wire valid;
    wire [11:0] cx,cy;
    wire [1:0] color;
    tracker_target_select #(.WIDTH(1280),.HEIGHT(720)) dut(
        .red_valid(rv),.green_valid(gv),.blue_valid(bv),.yellow_valid(yv),
        .red_cx(rx),.red_cy(ry),.green_cx(gx),.green_cy(gy),
        .blue_cx(bx),.blue_cy(by),.yellow_cx(yx),.yellow_cy(yy),
        .valid(valid),.cx(cx),.cy(cy),.color(color));

    function integer reference_distance;
        input [11:0] px, py;
        integer dx, dy;
        begin
            dx = px - 640;
            dy = py - 360;
            if (dx < 0) dx = -dx;
            if (dy < 0) dy = -dy;
            reference_distance = dx + dy;
        end
    endfunction

    task check_reference;
        integer expected_valid, expected_color, best_distance, candidate_distance;
        reg [11:0] expected_cx, expected_cy;
        begin
            expected_valid = 0;
            expected_color = 0;
            expected_cx = 0;
            expected_cy = 0;
            best_distance = 8191;
            if (rv) begin
                expected_valid = 1;
                expected_cx = rx;
                expected_cy = ry;
                best_distance = reference_distance(rx,ry);
            end
            if (gv) begin
                candidate_distance = reference_distance(gx,gy);
                if (!expected_valid || candidate_distance < best_distance) begin
                    expected_valid = 1;
                    expected_color = 1;
                    expected_cx = gx;
                    expected_cy = gy;
                    best_distance = candidate_distance;
                end
            end
            if (bv) begin
                candidate_distance = reference_distance(bx,by);
                if (!expected_valid || candidate_distance < best_distance) begin
                    expected_valid = 1;
                    expected_color = 2;
                    expected_cx = bx;
                    expected_cy = by;
                    best_distance = candidate_distance;
                end
            end
            if (yv) begin
                candidate_distance = reference_distance(yx,yy);
                if (!expected_valid || candidate_distance < best_distance) begin
                    expected_valid = 1;
                    expected_color = 3;
                    expected_cx = yx;
                    expected_cy = yy;
                    best_distance = candidate_distance;
                end
            end
            #1;
            if (valid !== expected_valid[0] || color !== expected_color[1:0] ||
                cx !== expected_cx || cy !== expected_cy)
                $fatal(1,"target selection differs from serial reference");
        end
    endtask

    integer iteration;
    initial begin
        #1;
        if(valid) $fatal(1,"empty candidates reported valid");
        rv=1; rx=20; ry=20;
        gv=1; gx=635; gy=350;
        #1;
        if(!valid || color!=1 || cx!=635 || cy!=350)
            $fatal(1,"nearest green candidate not selected");
        bv=1; bx=640; by=360;
        #1;
        if(color!=2 || cx!=640 || cy!=360)
            $fatal(1,"nearest blue candidate not selected");
        yv=1; yx=640; yy=360;
        #1;
        if(color!=2) $fatal(1,"candidate tie should retain first nearest colour");

        rv=1; gv=1; bv=1; yv=1;
        rx=0; ry=0; gx=1279; gy=719; bx=4095; by=4095; yx=640; yy=360;
        check_reference();
        rx=640; ry=360; gx=641; gy=359; bx=639; by=361; yx=641; yy=361;
        check_reference();
        rx=639; ry=360; gx=640; gy=361; bx=641; by=360; yx=640; yy=359;
        check_reference();
        // All four candidates are equally distant from the image centre.
        // The serial reference contract must retain red before green, blue,
        // and yellow rather than depending on the comparison-tree shape.
        rv=1; gv=1; bv=1; yv=1;
        rx=639; ry=360; gx=640; gy=359; bx=641; by=360; yx=640; yy=361;
        #1;
        if(!valid || color!=0 || cx!=639 || cy!=360)
            $fatal(1,"equal-distance tie must prefer red");
        rv=0;
        #1;
        if(!valid || color!=1 || cx!=640 || cy!=359)
            $fatal(1,"equal-distance tie must prefer green after red is absent");
        gv=0;
        #1;
        if(!valid || color!=2 || cx!=641 || cy!=360)
            $fatal(1,"equal-distance tie must prefer blue after red and green are absent");
        bv=0;
        #1;
        if(!valid || color!=3 || cx!=640 || cy!=361)
            $fatal(1,"equal-distance tie must select yellow when it is the only candidate");
        rv=1; gv=1; bv=1; yv=1;
        for (iteration=0; iteration<2000; iteration=iteration+1) begin
            rv=$random;
            gv=$random;
            bv=$random;
            yv=$random;
            rx=$random; ry=$random;
            gx=$random; gy=$random;
            bx=$random; by=$random;
            yx=$random; yy=$random;
            check_reference();
        end
        $display("PASS target select: nearest, ties, image edges, and 2000 reference comparisons");
        $finish;
    end
endmodule
