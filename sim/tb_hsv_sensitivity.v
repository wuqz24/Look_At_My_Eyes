`timescale 1ns/1ps
// Per-pixel colour classifier regression (rev E, light-adaptive).
//
//   red   bright (V>=96): S>=28 %,   chroma>=12, hue +-45 deg
//         dim            : S>=44 %,   chroma>=26, hue +-45 deg
//   blue  bright        : S>=16 %,   chroma>=16, hue +-52 deg
//         dim            : S>=28 %,   chroma>=24, hue +-52 deg
//
// The dim floors exist because a dim scene is dominated by per-channel sensor
// noise: with a single relaxed threshold a grey wall dithers into thousands of
// "red" pixels (the HITS row showed R999 with an empty scene).
module tb_hsv_sensitivity;
    reg [23:0] rgb = 24'h000000;
    wire rh, bh;

    tracker_color_gate dut(.rgb(rgb), .red_hit(rh), .blue_hit(bh));

    task check;
        input [23:0] p;
        input exp_red, exp_blue;
        input [8*36-1:0] name;
        begin
            rgb = p;
            #1;
            if ({rh, bh} !== {exp_red, exp_blue})
                $fatal(1, "%0s rgb=%h got red=%b blue=%b (%b %b)",
                       name, p, rh, bh, exp_red, exp_blue);
        end
    endtask

    initial begin
        // --- measured targets, bright light -------------------------------
        check(24'hde8f7a, 1, 0, "measured red paper");
        check(24'h597697, 0, 1, "measured blue paper (dark)");
        check(24'h96afbe, 0, 1, "blue paper under the lamp");
        check(24'h3f60d6, 0, 1, "moulded blue cap");

        // --- same paper in dim light (V < 96, stricter floors) ------------
        check(24'h593931, 1, 0, "dim red paper");
        check(24'h3c2620, 1, 0, "darker red paper");
        check(24'h283c48, 0, 1, "dim blue paper");

        // --- neutral surfaces and their dither must not be a colour -------
        check(24'hc0a69a, 0, 0, "measured skin / hand");
        check(24'h6d5e56, 0, 0, "dim skin / hand");
        check(24'hdbdfd7, 0, 0, "measured white board");
        check(24'he1e8e4, 0, 0, "bright wall");
        check(24'he1e5e8, 0, 0, "bright wall, blue dither");
        check(24'h6e6f6b, 0, 0, "dim white board");
        check(24'h6e7270, 0, 0, "dim wall, blue dither");
        // The dim-room killer: a dim grey wall with strong per-channel noise.
        check(24'h695a4e, 0, 0, "dim wall, warm light");
        check(24'h46505a, 0, 0, "dim wall, blue dither");
        check(24'h303030, 0, 0, "dark grey desk");
        check(24'h808080, 0, 0, "mid grey");

        // --- saturated primaries ------------------------------------------
        check(24'hff0000, 1, 0, "pure red");
        check(24'h0000ff, 0, 1, "pure blue");
        check(24'hc02028, 1, 0, "dark red paper");
        check(24'h2040f0, 0, 1, "saturated blue");
        check(24'h1e2864, 0, 1, "Vinda logo blue");

        // --- other hues are not target classes ----------------------------
        check(24'h00ff00, 0, 0, "pure green");
        check(24'hffff00, 0, 0, "yellow");
        check(24'h00ffff, 0, 0, "cyan");
        check(24'hff00ff, 0, 0, "magenta");

        // --- too dark to be trusted ---------------------------------------
        check(24'h180c0c, 0, 0, "near black red");
        check(24'h0c1420, 0, 0, "near black blue");

        $display("PASS colour gate: paper bright/dim, noisy dim wall rejected, cap and disc blue");
        $finish;
    end
endmodule
