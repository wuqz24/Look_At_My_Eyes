// Video liveness monitor. A valid tag and an active pixel prove that the
// displayed frame is fresh; a tag that stops arriving eventually faults the
// video path and prevents stale target data from reaching the servo.
module video_health #(
    parameter integer CLK_HZ = 75000000,
    parameter integer TIMEOUT_MS = 120,
    parameter integer RECOVERY_FRAMES = 2
)(
    input wire clk,
    input wire rst_n,
    input wire frame_tick,
    input wire tag_alive,
    input wire tag_valid,
    input wire de,
    input wire rgb_nonzero,
    output reg healthy,
    output reg recovery,
    output reg fault
);
    localparam integer RAW_TIMEOUT_CYCLES = (CLK_HZ / 1000) * TIMEOUT_MS;
    localparam integer TIMEOUT_CYCLES = RAW_TIMEOUT_CYCLES < 2 ? 2 : RAW_TIMEOUT_CYCLES;
    localparam integer RECOVERY_LIMIT = RECOVERY_FRAMES < 1 ? 1 : RECOVERY_FRAMES;
    localparam integer AGE_W = (TIMEOUT_CYCLES <= 2) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
    localparam integer GOOD_W = (RECOVERY_LIMIT <= 2) ? 1 : $clog2(RECOVERY_LIMIT + 1);

    reg [AGE_W-1:0] age;
    reg [GOOD_W-1:0] good_frames;
    reg frame_open;
    reg frame_counted;
    wire good_sample = frame_open && !frame_counted && tag_alive && tag_valid && de && rgb_nonzero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            age          <= TIMEOUT_CYCLES[AGE_W-1:0];
            good_frames  <= 0;
            frame_open   <= 1'b0;
            frame_counted<= 1'b0;
            healthy      <= 1'b0;
            recovery     <= 1'b0;
            fault        <= 1'b1;
        end else begin
            recovery <= 1'b0;

            if (frame_tick) begin
                frame_open    <= 1'b1;
                frame_counted <= 1'b0;
            end

            if (age < TIMEOUT_CYCLES)
                age <= age + 1'b1;

            if (good_sample) begin
                frame_counted <= 1'b1;
                age <= 0;
                if (!healthy) begin
                    if (good_frames < RECOVERY_LIMIT)
                        good_frames <= good_frames + 1'b1;
                    if (good_frames >= RECOVERY_LIMIT-1) begin
                        healthy <= 1'b1;
                        fault <= 1'b0;
                        recovery <= 1'b1;
                        good_frames <= 0;
                    end
                end else begin
                    good_frames <= 0;
                end
            end

            if (age >= TIMEOUT_CYCLES-1 && !good_sample) begin
                healthy <= 1'b0;
                fault <= 1'b1;
                good_frames <= 0;
            end
        end
    end
endmodule
