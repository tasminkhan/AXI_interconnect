`timescale 1ns / 1ps
import param_pkg::*;

module b_arbiter #(
    parameter int MASTER_ID = 0,
    parameter int NT        = NUM_TARGETS
)(
    input  logic ACLK,
    input  logic ARESETn,

    //---------------- per-slot B inputs (broadcast from all slaves) --
    input  logic [ID_WIDTH-1:0]   b_id_s_i    [0:NT-1],
    input  logic [RESP_WIDTH-1:0] b_resp_s_i  [0:NT-1],
    input  logic [QOS_WIDTH-1:0]  b_qos_s_i   [0:NT-1],   // sideband, not AXI
    input  logic                  b_valid_s_i [0:NT-1],
    output logic [NT-1:0]         b_ready_s_o,

    //---------------- muxed B out to this master's B skid ------------
    output logic [ID_WIDTH-1:0]   b_id_o,
    output logic [RESP_WIDTH-1:0] b_resp_o,
    output logic                  b_valid_o,
    input  logic                  b_ready_i
);
    localparam int TW = (NT > 1) ? $clog2(NT) : 1;

    logic [TW-1:0] rr_ptr, next_rr;
    logic          grant_valid;
    logic [TW-1:0] gnt_idx;

    logic          hold_valid;
    logic [TW-1:0] hold_idx;

    logic [AGE_WIDTH-1:0] age [0:NT-1];
    logic [QOS_WIDTH-1:0] eff [0:NT-1];

    // candidate = this slot has a B tagged to MASTER_ID
    function automatic logic mine(input int t);
        logic [ID_WIDTH-1:0]          idv;
        logic [MASTER_TAG_WIDTH-1:0]  tagv;
        idv  = b_id_s_i[t];
        tagv = idv[ID_WIDTH-1 -: MASTER_TAG_WIDTH];
        return b_valid_s_i[t] && (tagv == MASTER_ID[MASTER_TAG_WIDTH-1:0]);
    endfunction

    always_comb begin
        for (int t = 0; t < NT; t++)
            eff[t] = (age[t] >= STARVE_LIMIT) ? QOS_MAX : b_qos_s_i[t];
    end

    always_comb begin
        int t;
        logic [QOS_WIDTH-1:0] best;

        t           = 0;
        best        = '0;
        grant_valid = 1'b0;
        gnt_idx     = '0;
        next_rr     = rr_ptr;
        b_id_o      = '0;
        b_resp_o    = RESP_OKAY;
        b_ready_s_o = '0;

        if (hold_valid && mine(int'(hold_idx))) begin
            grant_valid = 1'b1;
            gnt_idx     = hold_idx;
        end else begin
            for (int k = 0; k < NT; k++) begin
                t = (rr_ptr + k) % NT;
                if (mine(t) && (!grant_valid || (eff[t] > best))) begin
                    grant_valid = 1'b1;
                    gnt_idx     = TW'(t);
                    best        = eff[t];
                end
            end
        end

        if (grant_valid) begin
            b_id_o             = b_id_s_i  [gnt_idx];
            b_resp_o           = b_resp_s_i[gnt_idx];
            b_ready_s_o[gnt_idx] = b_ready_i;
            next_rr            = TW'((gnt_idx + 1) % NT);
        end
        b_valid_o = grant_valid;
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rr_ptr     <= '0;
            hold_valid <= 1'b0;
            hold_idx   <= '0;
            for (int t = 0; t < NT; t++) age[t] <= '0;
        end else begin
            if (b_valid_o && b_ready_i) rr_ptr <= next_rr;

            if (b_valid_o && b_ready_i) begin
                hold_valid <= 1'b0;
            end else if (b_valid_o) begin
                hold_valid <= 1'b1;
                hold_idx   <= gnt_idx;
            end else begin
                hold_valid <= 1'b0;
            end

            for (int t = 0; t < NT; t++) begin
                if (!mine(t))
                    age[t] <= '0;
                else if (b_valid_o && b_ready_i && (gnt_idx == TW'(t)))
                    age[t] <= '0;
                else if (age[t] != {AGE_WIDTH{1'b1}})
                    age[t] <= age[t] + 1'b1;
            end
        end
    end
endmodule
