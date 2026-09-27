`timescale 1ns / 1ps
import param_pkg::*;

module addr_arbiter #(
    parameter int NM = NUM_MASTERS,
    parameter int MW = MASTER_IDX_WIDTH
)(
    input  logic ACLK,
    input  logic ARESETn,

    //---------------- per-master request in / grant back -------------
    input  logic [NM-1:0]            arbin_valid,   // master m wants this slot, eligible
    output logic [NM-1:0]            arbin_ready,   // granted master's ready

    //---------------- per-master candidate payloads ------------------
    input  logic [ID_WIDTH-1:0]      id_i   [0:NM-1],
    input  logic [ADDRESS_WIDTH-1:0] addr_i [0:NM-1],
    input  logic [LEN_WIDTH-1:0]     len_i  [0:NM-1],
    input  logic [QOS_WIDTH-1:0]     qos_i  [0:NM-1],

    //---------------- muxed winner toward the slave ------------------
    output logic [ID_WIDTH-1:0]      id_o,
    output logic [ADDRESS_WIDTH-1:0] addr_o,
    output logic [LEN_WIDTH-1:0]     len_o,
    output logic [QOS_WIDTH-1:0]     qos_o,
    output logic                     arbout_valid,
    input  logic                     arbout_ready,  // slave's AWREADY / ARREADY

    //---------------- grant exposure (order tracking, scoreboard) ----
    output logic                     grant_valid,   // grant AND handshake
    output logic [MW-1:0]            grant_idx      // winning master index
);
    logic [MW-1:0] rr_ptr, next_ptr;
    logic          gnt_valid;
    logic [MW-1:0] gnt_idx;

    // grant hold: winner latched while an offer is outstanding
    logic          hold_valid;
    logic [MW-1:0] hold_idx;

    //-----------------------------------------------------------------
    // Pick. While an offer is outstanding the held master IS the pick,
    // Otherwise: round-robin,
    //-----------------------------------------------------------------
    always_comb begin
        int m;
        gnt_valid = 1'b0;
        gnt_idx   = '0;

        if (hold_valid && arbin_valid[hold_idx]) begin
            gnt_valid = 1'b1;
            gnt_idx   = hold_idx;
        end else begin
            for (int k = 0; k < NM; k++) begin
                m = (rr_ptr + k) % NM;
                if (!gnt_valid && arbin_valid[m]) begin
                    gnt_valid = 1'b1;
                    gnt_idx   = MW'(m);
                end
            end
        end
        next_ptr = MW'((gnt_idx + 1) % NM);
    end

    //-----------------------------------------------------------------
    // Mux the winner's payload to the slave; steer ready back to it.
    //-----------------------------------------------------------------
    always_comb begin
        id_o         = '0;
        addr_o       = '0;
        len_o        = '0;
        qos_o        = '0;
        arbout_valid = 1'b0;
        arbin_ready  = '0;
        if (gnt_valid) begin
            id_o                = id_i  [gnt_idx];
            addr_o              = addr_i[gnt_idx];
            len_o               = len_i [gnt_idx];
            qos_o               = qos_i [gnt_idx];
            arbout_valid        = 1'b1;
            arbin_ready[gnt_idx]= arbout_ready;   // ready only to the winner
        end
    end

    assign grant_valid = gnt_valid & arbout_valid & arbout_ready;
    assign grant_idx   = gnt_idx;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rr_ptr     <= '0;
            hold_valid <= 1'b0;
            hold_idx   <= '0;
        end else begin
            if (grant_valid) rr_ptr <= next_ptr;

            if (grant_valid) begin
                hold_valid <= 1'b0;                  // handshake done
            end else if (arbout_valid) begin
                hold_valid <= 1'b1;                  // offer made, not taken
                hold_idx   <= gnt_idx;
            end else begin
                hold_valid <= 1'b0;                  // nothing offered
            end
        end
    end
endmodule
