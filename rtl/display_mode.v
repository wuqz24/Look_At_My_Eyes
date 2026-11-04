module display_mode (
    input wire clk,
    input wire rst_n,
    input wire frame_tick,
    input wire sw1,
    input wire sw2,
    // Adaptive luminance threshold, computed by hdmi_mixer from the frame mean
    // and latched at the frame boundary.  A fixed threshold made the binary
    // view all-white in bright light and all-black in dim light.
    input wire [7:0] threshold,
    input wire [23:0] rgb_in,
    output reg [1:0] mode,
    output reg [23:0] rgb_out
);
    reg sw1_meta, sw1_sync;
    reg sw2_meta, sw2_sync;
    wire [1:0] requested_mode = {sw2_sync, sw1_sync};
    wire [15:0] luminance_sum =
        (rgb_in[23:16] * 8'd77) +
        (rgb_in[15:8]  * 8'd150) +
        (rgb_in[7:0]   * 8'd29);
    wire [7:0] luminance = luminance_sum[15:8];
    wire [23:0] gray_rgb = {luminance, luminance, luminance};
    wire [23:0] binary_rgb = (luminance >= threshold) ? 24'hffffff : 24'h000000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw1_meta <= 1'b0;
            sw1_sync <= 1'b0;
            sw2_meta <= 1'b0;
            sw2_sync <= 1'b0;
            mode <= 2'd0;
        end else begin
            sw1_meta <= sw1;
            sw1_sync <= sw1_meta;
            sw2_meta <= sw2;
            sw2_sync <= sw2_meta;
            if (frame_tick) begin
                case (requested_mode)
                    2'b01: mode <= 2'd1;
                    2'b10: mode <= 2'd2;
                    default: mode <= 2'd0;
                endcase
            end
        end
    end

    always @* begin
        case (mode)
            2'd1: rgb_out = gray_rgb;
            2'd2: rgb_out = binary_rgb;
            default: rgb_out = rgb_in;
        endcase
    end
endmodule
