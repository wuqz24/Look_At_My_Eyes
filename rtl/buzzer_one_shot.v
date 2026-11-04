module buzzer_one_shot #(
    parameter integer CLK_HZ = 75000000,
    parameter integer TONE_HZ = 2000,
    parameter integer DURATION_MS = 100
)(
    input wire clk,
    input wire rst_n,
    input wire trigger,
    output wire buzzer
);
    localparam integer HALF_PERIOD = (CLK_HZ / (TONE_HZ * 2) < 1) ? 1 : CLK_HZ / (TONE_HZ * 2);
    localparam integer DURATION_TICKS = (CLK_HZ / 1000 * DURATION_MS < 1) ? 1 : CLK_HZ / 1000 * DURATION_MS;
    reg trigger_d;
    reg active;
    reg [31:0] tone_count;
    reg [31:0] duration_count;
    reg tone_level;

    assign buzzer = (active && tone_level) ? 1'b0 : 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trigger_d <= 1'b0;
            active <= 1'b0;
            tone_count <= 0;
            duration_count <= 0;
            tone_level <= 1'b0;
        end else begin
            trigger_d <= trigger;
            if (!active) begin
                tone_count <= 0;
                duration_count <= 0;
                tone_level <= 1'b0;
                if (trigger && !trigger_d) begin
                    active <= 1'b1;
                    tone_level <= 1'b1;
                end
            end else begin
                if (duration_count >= DURATION_TICKS-1) begin
                    active <= 1'b0;
                    duration_count <= 0;
                    tone_count <= 0;
                    tone_level <= 1'b0;
                end else begin
                    duration_count <= duration_count + 1'b1;
                    if (tone_count >= HALF_PERIOD-1) begin
                        tone_count <= 0;
                        tone_level <= ~tone_level;
                    end else begin
                        tone_count <= tone_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule
