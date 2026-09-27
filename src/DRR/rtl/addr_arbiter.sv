`timescale 1ns / 1ps
import param_pkg::*;

module addr_arbiter #(
    parameter int NM = NUM_MASTERS,
    parameter int MW = MASTER_IDX_WIDTH
)(
    input  logic ACLK,
    input  logic ARESETn,

    //---------------- per-master request in / grant back -------------
    input  logic [NM-1:0]            arbin_valid,
    output logic [NM-1:0]            arbin_ready,

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
    input  logic                     arbout_ready,

    //---------------- grant exposure (order tracking, scoreboard) ----
    output logic                     grant_valid,
    output logic [MW-1:0]            grant_idx
);
    logic [MW-1:0] rr_ptr, next_ptr;
    logic          gnt_valid;
    logic [MW-1:0] gnt_idx;

    logic          hold_valid;
    logic [MW-1:0] hold_idx;

    //-----------------------------------------------------------------
    // Deficit state
    //-----------------------------------------------------------------
    logic [DEFICIT_WIDTH-1:0] deficit  [0:NM-1];
    logic [COST_WIDTH-1:0]    cost     [0:NM-1];
    logic [NM-1:0]            eligible;
    logic                     any_req, any_elig, replenish;

    //-----------------------------------------------------------------
    // Cost of each pending request, in BEATS. 
    //-----------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < NM; m++)
            cost[m] = COST_WIDTH'(len_i[m]) + COST_WIDTH'(1);
    end

    //-----------------------------------------------------------------
    // Admission gate
    //-----------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < NM; m++)
            eligible[m] = arbin_valid[m] &&
                          (deficit[m] >= DEFICIT_WIDTH'(cost[m]));
    end

    assign any_req   = |arbin_valid;
    assign any_elig  = |eligible;
    // Round boundary: someone wants to issue, nobody may. Note this can
    // never fire while an offer is outstanding, since a held winner is
    // by definition still eligible.
    assign replenish = any_req & ~any_elig;

    //-----------------------------------------------------------------
    // Pick: among the ELIGIBLE, highest QoS wins; 
    //-----------------------------------------------------------------
    always_comb begin
        int m;
        logic [QOS_WIDTH-1:0] best;

        gnt_valid = 1'b0;
        gnt_idx   = '0;
        best      = '0;
        m         = 0;

        if (hold_valid && arbin_valid[hold_idx]) begin
            gnt_valid = 1'b1;
            gnt_idx   = hold_idx;
        end else begin
            for (int k = 0; k < NM; k++) begin
                m = (rr_ptr + k) % NM;
                if (eligible[m] && (!gnt_valid || (qos_i[m] > best))) begin
                    gnt_valid = 1'b1;
                    gnt_idx   = MW'(m);
                    best      = qos_i[m];
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
            id_o                 = id_i  [gnt_idx];
            addr_o               = addr_i[gnt_idx];
            len_o                = len_i [gnt_idx];
            qos_o                = qos_i [gnt_idx];
            arbout_valid         = 1'b1;
            arbin_ready[gnt_idx] = arbout_ready;
        end
    end

    assign grant_valid = gnt_valid & arbout_valid & arbout_ready;
    assign grant_idx   = gnt_idx;

    //-----------------------------------------------------------------
    // Pointer, hold, and deficit update.
    //-----------------------------------------------------------------
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rr_ptr     <= '0;
            hold_valid <= 1'b0;
            hold_idx   <= '0;
            for (int m = 0; m < NM; m++)
                deficit[m] <= DEFICIT_WIDTH'(master_quantum(m));
        end else begin
            if (grant_valid) rr_ptr <= next_ptr;

            if (grant_valid) begin
                hold_valid <= 1'b0;
            end else if (arbout_valid) begin
                hold_valid <= 1'b1;
                hold_idx   <= gnt_idx;
            end else begin
                hold_valid <= 1'b0;
            end

            //--------- deficit: charge on grant, credit on round end ---
            if (replenish) begin
                // Credit only the masters actually asking. An idle master
                // keeps what it had; the cap below bounds how much any
                // master can bank while waiting.
                for (int m = 0; m < NM; m++) begin
                    if (arbin_valid[m]) begin
                        if ((deficit[m] + DEFICIT_WIDTH'(master_quantum(m)))
                                > DEFICIT_WIDTH'(DEFICIT_CAP))
                            deficit[m] <= DEFICIT_WIDTH'(DEFICIT_CAP);
                        else
                            deficit[m] <= deficit[m]
                                        + DEFICIT_WIDTH'(master_quantum(m));
                    end
                end
            end else if (grant_valid) begin
                deficit[grant_idx] <= deficit[grant_idx]
                                    - DEFICIT_WIDTH'(cost[grant_idx]);
            end
        end
    end
endmodule
