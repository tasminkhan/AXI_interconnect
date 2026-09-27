module skidbuffer #(
    parameter int WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst_n,      // active-low synchronous reset
    
    // upstream (input side) 
    input  logic [WIDTH-1:0] in_data,
    input  logic             in_valid,
    output logic             in_ready,

    // downstream (output side)
    output logic [WIDTH-1:0] out_data,
    output logic             out_valid,
    input  logic             out_ready

    // ---- DEBUG OBSERVATION PORTS (not part of the protocol) ----
    //output logic [WIDTH-1:0] dbg_out_reg,   // contents of the output slot
    //output logic [WIDTH-1:0] dbg_tmp_reg,   // contents of the skid slot
    //output logic             dbg_out_full,  // output slot occupied?
    //output logic             dbg_tmp_full,  // skid slot occupied?
    //output logic             dbg_in_ready_early // combinational next-cycle ready
);
    logic [WIDTH-1:0] out_reg, tmp_reg;
    logic             out_full, tmp_full;   // occupancy flags
    assign out_data  = out_reg;
    assign out_valid = out_full;

    // Ready NEXT cycle if downstream is draining now, or the skid slot will still be free.
    wire in_ready_early = out_ready | (~tmp_full & (~out_full | ~in_valid));
    
    // ---- drive the debug ports from the internal state ----
    //assign dbg_out_reg        = out_reg;
    //assign dbg_tmp_reg        = tmp_reg;
    //assign dbg_out_full       = out_full;
    //assign dbg_tmp_full       = tmp_full;
    //assign dbg_in_ready_early = in_ready_early;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_ready <= 1'b0;
            out_full <= 1'b0;
            tmp_full <= 1'b0;
            out_reg  <= 0;
            tmp_reg <= 0;
        end else begin
            in_ready <= in_ready_early;
            if (in_ready) begin
                if (out_ready || !out_full) begin
                    out_reg  <= in_data;
                    out_full <= in_valid;        // full only if a beat really arrived
                end else if (in_valid) begin
                    tmp_reg  <= in_data;
                    tmp_full <= 1'b1;
                end
            end else if (out_ready) begin
                out_reg  <= tmp_reg;
                out_full <= tmp_full;
                tmp_full <= 1'b0;
            end
        end
    end
endmodule