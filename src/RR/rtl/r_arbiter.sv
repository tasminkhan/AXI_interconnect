`timescale 1ns / 1ps
import param_pkg::*;

module r_arbiter #(
    parameter int MASTER_ID = 0,
    parameter int NT        = NUM_TARGETS
)(
    input  logic ACLK,
    input  logic ARESETn,

    //---------------- per-slot R inputs (broadcast from all slaves) --
    input  logic [ID_WIDTH-1:0]   r_id_s_i    [0:NT-1],
    input  logic [DATA_WIDTH-1:0] r_data_s_i  [0:NT-1],
    input  logic [RESP_WIDTH-1:0] r_resp_s_i  [0:NT-1],
    input  logic                  r_last_s_i  [0:NT-1],
    input  logic                  r_valid_s_i [0:NT-1],
    output logic [NT-1:0]         r_ready_s_o,

    //---------------- muxed R out to this master's R skid ------------
    output logic [ID_WIDTH-1:0]   r_id_o,
    output logic [DATA_WIDTH-1:0] r_data_o,
    output logic [RESP_WIDTH-1:0] r_resp_o,
    output logic                  r_last_o,
    output logic                  r_valid_o,
    input  logic                  r_ready_i
);
    localparam int TW = (NT > 1) ? $clog2(NT) : 1;

    logic [TW-1:0] rr_ptr, next_rr, lock_sel, active_sel;
    logic          grant_valid, locked;

    function automatic logic mine(input int t);
        logic [ID_WIDTH-1:0]          idv;
        logic [MASTER_TAG_WIDTH-1:0]  tagv;
        idv  = r_id_s_i[t];
        tagv = idv[ID_WIDTH-1 -: MASTER_TAG_WIDTH];
        return r_valid_s_i[t] && (tagv == MASTER_ID[MASTER_TAG_WIDTH-1:0]);
    endfunction

    always_comb begin
        int t;
        t           = 0;          // assigned on every path (no inferred latch)
        next_rr     = rr_ptr;
        grant_valid = 1'b0;
        r_id_o = '0; r_data_o = '0; r_resp_o = RESP_OKAY; r_last_o = 1'b0;
        r_valid_o   = 1'b0;
        active_sel  = lock_sel;
        r_ready_s_o = '0;

        if (locked) begin
            // stay on the locked slot (tag matches by construction)
            r_id_o              = r_id_s_i   [lock_sel];
            r_data_o            = r_data_s_i [lock_sel];
            r_resp_o            = r_resp_s_i [lock_sel];
            r_last_o            = r_last_s_i [lock_sel];
            r_valid_o           = r_valid_s_i[lock_sel];
            r_ready_s_o[lock_sel] = r_ready_i;
            grant_valid         = r_valid_o;
        end else begin
            for (int k = 0; k < NT; k++) begin
                t = (rr_ptr + k) % NT;
                if (!grant_valid && mine(t)) begin
                    r_id_o         = r_id_s_i  [t];
                    r_data_o       = r_data_s_i[t];
                    r_resp_o       = r_resp_s_i[t];
                    r_last_o       = r_last_s_i[t];
                    r_ready_s_o[t] = r_ready_i;
                    r_valid_o      = 1'b1;
                    grant_valid    = 1'b1;
                    active_sel     = TW'(t);
                    next_rr        = TW'((t + 1) % NT);
                end
            end
        end
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rr_ptr <= '0; locked <= 1'b0; lock_sel <= '0;
        end else begin
            if (!locked) begin
                if (grant_valid) begin
                    lock_sel <= active_sel;
                    if (r_valid_o && r_ready_i && r_last_o) begin
                        locked <= 1'b0;              // single-beat burst
                        rr_ptr <= next_rr;
                    end else begin
                        locked <= 1'b1;
                    end
                end
            end else if (r_valid_o && r_ready_i && r_last_o) begin
                locked <= 1'b0;
                rr_ptr <= TW'((lock_sel + 1) % NT);
            end
        end
    end
endmodule
