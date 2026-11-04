// Asynchronous assertion, synchronous deassertion reset synchronizer.
// The extra terminal stage keeps the output low for a complete clock after
// the synchronizer pipeline has been filled, which gives downstream logic a
// deterministic release edge.
module reset_sync #(
    parameter integer STAGES = 2
)(
    input wire clk,
    input wire arst_n,
    output wire rst_n
);
    reg [STAGES:0] sync_ff;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            sync_ff <= {(STAGES+1){1'b0}};
        else
            sync_ff <= {sync_ff[STAGES-1:0],1'b1};
    end

    assign rst_n = sync_ff[STAGES];
endmodule
