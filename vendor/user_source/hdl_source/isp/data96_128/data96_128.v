module data_96bit_to_128bit (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire         I_96b_frame_start,
    input  wire         I_96b_line_end,
    input  wire         I_96b_valid,
    input  wire [95:0]  I_96b_data,
    output wire         I_96b_ready,
    output reg          O_128b_frame_start,
    output reg          O_128b_line_end,
    output reg          O_128b_valid,
    output reg  [127:0] O_128b_data,
    input  wire         O_128b_ready
);
    reg [95:0] previous_input;
    reg [1:0] input_count;
    reg previous_frame_start;
    reg output_frame_start;
    reg output_line_end;
    reg [127:0] output_data;
    reg output_valid;

    wire output_slot_available = !output_valid || O_128b_ready;
    wire input_produces_output = (input_count != 2'd0);
    assign I_96b_ready = output_slot_available;

    always @* begin
        output_data = 128'd0;
        output_frame_start = 1'b0;
        output_line_end = 1'b0;
        case (input_count)
            2'd1: begin
                output_data = {previous_input, I_96b_data[95:64]};
                output_frame_start = previous_frame_start;
                output_line_end = I_96b_line_end;
            end
            2'd2: begin
                output_data = {previous_input[63:0], I_96b_data[95:32]};
                output_line_end = I_96b_line_end;
            end
            2'd3: begin
                output_data = {previous_input[31:0], I_96b_data};
                output_line_end = I_96b_line_end;
            end
            default: begin
                output_data = 128'd0;
                output_frame_start = 1'b0;
                output_line_end = 1'b0;
            end
        endcase
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            previous_input <= 96'd0;
            input_count <= 2'd0;
            previous_frame_start <= 1'b0;
            O_128b_frame_start <= 1'b0;
            O_128b_line_end <= 1'b0;
            O_128b_valid <= 1'b0;
            O_128b_data <= 128'd0;
        end else if (I_96b_ready) begin
            if (I_96b_valid) begin
                previous_input <= I_96b_data;
                previous_frame_start <= I_96b_frame_start;
                // Frame and line boundaries are byte-stream boundaries. Any
                // incomplete 128-bit word must not be joined to the next
                // frame or line.
                if (I_96b_frame_start) begin
                    input_count <= 2'd1;
                    O_128b_valid <= 1'b0;
                    O_128b_frame_start <= 1'b0;
                    O_128b_line_end <= 1'b0;
                end else begin
                    input_count <= I_96b_line_end ? 2'd0 : input_count + 2'd1;
                    O_128b_valid <= input_produces_output;
                    O_128b_data <= output_data;
                    O_128b_frame_start <= output_frame_start;
                    O_128b_line_end <= output_line_end;
                end
            end else if (output_slot_available) begin
                O_128b_valid <= 1'b0;
                O_128b_frame_start <= 1'b0;
                O_128b_line_end <= 1'b0;
            end
        end
    end
endmodule
