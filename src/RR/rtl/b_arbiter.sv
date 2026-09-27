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

    // candidate = this slot has a B tagged to MASTER_ID
    function automatic logic mine(input int t);
        logic [ID_WIDTH-1:0]          idv;
        logic [MASTER_TAG_WIDTH-1:0]  tagv;
        idv  = b_id_s_i[t];
        tagv = idv[ID_WIDTH-1 -: MASTER_TAG_WIDTH];
        return b_valid_s_i[t] && (tagv == MASTER_ID[MASTER_TAG_WIDTH-1:0]);
    endfunction

    always_comb begin
        int t;
        t           = 0;
        next_rr     = rr_ptr;
        grant_valid = 1'b0;
        b_id_o      = '0;
        b_resp_o    = RESP_OKAY;
        b_ready_s_o = '0;

        for (int k = 0; k < NT; k++) begin
            t = (rr_ptr + k) % NT;
            if (!grant_valid && mine(t)) begin
                b_id_o          = b_id_s_i  [t];
                b_resp_o        = b_resp_s_i[t];
                b_ready_s_o[t]  = b_ready_i;
                grant_valid     = 1'b1;
                next_rr         = TW'((t + 1) % NT);
            end
        end
        b_valid_o = grant_valid;
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn)                  rr_ptr <= '0;
        else if (b_valid_o & b_ready_i) rr_ptr <= next_rr;
    end
endmodule
