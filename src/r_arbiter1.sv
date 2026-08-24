`timescale 1ns / 1ps
import param_pkg::*;

// Two-target R arbiter (S1 + ERR). Round-robin between the two; once a
// target is granted it holds (locked) until its RLAST beat is accepted,
// so bursts are not interleaved.
module r_arbiter1 (
    input  logic ACLK, ARESETn,
    input  logic [ID_WIDTH-1:0]   RID_S1,   RID_ERR,
    input  logic [DATA_WIDTH-1:0] RDATA_S1, RDATA_ERR,
    input  logic [RESP_WIDTH-1:0] RRESP_S1, RRESP_ERR,
    input  logic                  RLAST_S1, RLAST_ERR,
    input  logic                  RVALID_S1, RVALID_ERR,
    output logic                  RREADY_S1, RREADY_ERR,
    output logic [ID_WIDTH-1:0]   RID_MUX,
    output logic [DATA_WIDTH-1:0] RDATA_MUX,
    output logic [RESP_WIDTH-1:0] RRESP_MUX,
    output logic                  RLAST_MUX,
    output logic                  RVALID_MUX,
    input  logic                  RREADY_DMUX
);
    logic r_rr_ptr, r_next_rr;      // 0 -> prefer S1, 1 -> prefer ERR
    logic r_grant_valid, r_locked, r_lock_sel, active_sel;

    always_comb begin
        r_next_rr     = r_rr_ptr;
        r_grant_valid = 1'b0;
        RID_MUX = '0; RDATA_MUX = '0; RRESP_MUX = RESP_OKAY; RLAST_MUX = 1'b0;
        RVALID_MUX = 1'b0;
        RREADY_S1 = 1'b0; RREADY_ERR = 1'b0;
        active_sel = r_lock_sel;

        if (r_locked) begin
            if (r_lock_sel == 1'b0) begin
                RID_MUX=RID_S1; RDATA_MUX=RDATA_S1; RRESP_MUX=RRESP_S1;
                RLAST_MUX=RLAST_S1; RVALID_MUX=RVALID_S1; RREADY_S1=RREADY_DMUX;
            end else begin
                RID_MUX=RID_ERR; RDATA_MUX=RDATA_ERR; RRESP_MUX=RRESP_ERR;
                RLAST_MUX=RLAST_ERR; RVALID_MUX=RVALID_ERR; RREADY_ERR=RREADY_DMUX;
            end
            r_grant_valid = RVALID_MUX;
        end else begin
            for (int k = 0; k < 2; k++) begin
                if (!r_grant_valid) begin
                    case ((r_rr_ptr + k[0]) & 1'b1)
                        1'b0: if (RVALID_S1) begin
                                  RID_MUX=RID_S1; RDATA_MUX=RDATA_S1; RRESP_MUX=RRESP_S1;
                                  RLAST_MUX=RLAST_S1; RREADY_S1=RREADY_DMUX;
                                  RVALID_MUX=1'b1; r_grant_valid=1'b1;
                                  active_sel=1'b0; r_next_rr=1'b1;
                              end
                        1'b1: if (RVALID_ERR) begin
                                  RID_MUX=RID_ERR; RDATA_MUX=RDATA_ERR; RRESP_MUX=RRESP_ERR;
                                  RLAST_MUX=RLAST_ERR; RREADY_ERR=RREADY_DMUX;
                                  RVALID_MUX=1'b1; r_grant_valid=1'b1;
                                  active_sel=1'b1; r_next_rr=1'b0;
                              end
                        default: ;
                    endcase
                end
            end
        end
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            r_rr_ptr <= 1'b0; r_locked <= 1'b0; r_lock_sel <= 1'b0;
        end else begin
            if (!r_locked) begin
                if (r_grant_valid) begin
                    r_lock_sel <= active_sel;
                    r_locked   <= 1'b1;
                    if (RVALID_MUX && RREADY_DMUX && RLAST_MUX) begin
                        r_locked <= 1'b0;
                        r_rr_ptr <= r_next_rr;
                    end
                end
            end else if (RVALID_MUX && RREADY_DMUX && RLAST_MUX) begin
                r_locked <= 1'b0;
                r_rr_ptr <= ~r_lock_sel;
            end
        end
    end
endmodule
