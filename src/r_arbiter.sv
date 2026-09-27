`timescale 1ns / 1ps
import param_pkg::*;

// R-channel round-robin arbiter + mux. A granted target holds until its
// RLAST beat is accepted, so a burst is not interleaved.
module r_arbiter (
    input  logic ACLK, ARESETn,
    input  logic [ID_WIDTH-1:0]   RID_S0,   RID_S1,   RID_ERR,
    input  logic [DATA_WIDTH-1:0] RDATA_S0, RDATA_S1, RDATA_ERR,
    input  logic [RESP_WIDTH-1:0] RRESP_S0, RRESP_S1, RRESP_ERR,
    input  logic                  RLAST_S0, RLAST_S1, RLAST_ERR,
    input  logic                  RVALID_S0, RVALID_S1, RVALID_ERR,
    output logic                  RREADY_S0, RREADY_S1, RREADY_ERR,
    output logic [ID_WIDTH-1:0]   RID_MUX,
    output logic [DATA_WIDTH-1:0] RDATA_MUX,
    output logic [RESP_WIDTH-1:0] RRESP_MUX,
    output logic                  RLAST_MUX,
    output logic                  RVALID_MUX,
    input  logic                  RREADY_DMUX
);
    logic [SELECT_WIDTH-1:0] r_next_rr, r_rr_ptr;
    logic                    r_grant_valid, r_locked;
    logic [SELECT_WIDTH-1:0] r_lock_sel;

    // While mid-burst (locked) keep granting the same target until RLAST.
    logic [SELECT_WIDTH-1:0] active_sel;
    always_comb begin
        r_next_rr    = '0;
        r_grant_valid= 1'b0;
        RID_MUX      = '0;  RDATA_MUX = '0;  RRESP_MUX = RESP_OKAY;  RLAST_MUX = 1'b0;
        RREADY_S0 = 1'b0; RREADY_S1 = 1'b0; RREADY_ERR = 1'b0;
        active_sel   = r_lock_sel;

        if (r_locked) begin
            // stay on the locked target
            case (r_lock_sel)
                SEL_S0: begin RID_MUX=RID_S0; RDATA_MUX=RDATA_S0; RRESP_MUX=RRESP_S0;
                              RLAST_MUX=RLAST_S0; RVALID_MUX=RVALID_S0; RREADY_S0=RREADY_DMUX; end
                SEL_S1: begin RID_MUX=RID_S1; RDATA_MUX=RDATA_S1; RRESP_MUX=RRESP_S1;
                              RLAST_MUX=RLAST_S1; RVALID_MUX=RVALID_S1; RREADY_S1=RREADY_DMUX; end
                default:begin RID_MUX=RID_ERR;RDATA_MUX=RDATA_ERR;RRESP_MUX=RRESP_ERR;
                              RLAST_MUX=RLAST_ERR;RVALID_MUX=RVALID_ERR;RREADY_ERR=RREADY_DMUX; end
            endcase
            r_grant_valid = RVALID_MUX;
        end else begin
            RVALID_MUX = 1'b0;
            for (int k = 0; k < NUM_TARGETS; k++) begin
                if (!r_grant_valid) begin
                    case ((r_rr_ptr + k) % NUM_TARGETS)
                        SEL_S0: if (RVALID_S0) begin
                            RID_MUX=RID_S0; RDATA_MUX=RDATA_S0; RRESP_MUX=RRESP_S0;
                            RLAST_MUX=RLAST_S0; RREADY_S0=RREADY_DMUX;
                            RVALID_MUX=1'b1; r_grant_valid=1'b1; active_sel=SEL_S0; r_next_rr=SEL_S1; end
                        SEL_S1: if (RVALID_S1) begin
                            RID_MUX=RID_S1; RDATA_MUX=RDATA_S1; RRESP_MUX=RRESP_S1;
                            RLAST_MUX=RLAST_S1; RREADY_S1=RREADY_DMUX;
                            RVALID_MUX=1'b1; r_grant_valid=1'b1; active_sel=SEL_S1; r_next_rr=SEL_ERR; end
                        SEL_ERR: if (RVALID_ERR) begin
                            RID_MUX=RID_ERR; RDATA_MUX=RDATA_ERR; RRESP_MUX=RRESP_ERR;
                            RLAST_MUX=RLAST_ERR; RREADY_ERR=RREADY_DMUX;
                            RVALID_MUX=1'b1; r_grant_valid=1'b1; active_sel=SEL_ERR; r_next_rr=SEL_S0; end
                        default: ;
                    endcase
                end
            end
        end
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            r_rr_ptr   <= '0;
            r_locked   <= 1'b0;
            r_lock_sel <= '0;
        end else begin
            if (!r_locked) begin
                if (r_grant_valid) begin       // just granted a new burst
                    r_lock_sel <= active_sel;
                    if (RVALID_MUX && RREADY_DMUX && RLAST_MUX) begin  // single-beat burst
                        r_locked <= 1'b0;
                        r_rr_ptr <= r_next_rr;
                    end else begin
                        r_locked <= 1'b1;
                    end
                end
            end else if (RVALID_MUX && RREADY_DMUX && RLAST_MUX) begin // burst finished
                r_locked <= 1'b0;
                r_rr_ptr <= (r_lock_sel + 1) % NUM_TARGETS;
            end
        end
    end
endmodule
