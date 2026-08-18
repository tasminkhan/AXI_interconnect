//=====================================================================
// b_arbiter.sv - AXI B-channel round-robin arbiter + mux
//
// Muxes {BVALID,BID,BRESP} from whichever target has a response ready
// (round-robin priority), and demuxes BREADY back to the granted
// target only. Responses may return OUT OF ORDER across targets.
//=====================================================================
`timescale 1ns / 1ps
import param_pkg::*;

module b_arbiter (
    input  logic ACLK,
    input  logic ARESETn,

    //---------------- per-target B channel inputs ---------------------
    input  logic [ID_WIDTH-1:0]   BID_S0,   BID_S1,   BID_ERR,
    input  logic [RESP_WIDTH-1:0] BRESP_S0, BRESP_S1, BRESP_ERR,
    input  logic                  BVALID_S0, BVALID_S1, BVALID_ERR,

    //---------------- per-target BREADY outputs (demux) ---------------
    output logic BREADY_S0,
    output logic BREADY_S1,
    output logic BREADY_ERR,

    //---------------- muxed B channel out (to master's B skid) --------
    output logic [ID_WIDTH-1:0]   BID_MUX,
    output logic [RESP_WIDTH-1:0] BRESP_MUX,
    output logic                  BVALID_MUX,
    input  logic                  BREADY_DMUX
);

    logic [SELECT_WIDTH-1:0] b_next_rr, b_rr_ptr;
    logic                    b_grant_valid;

    always_comb begin
        b_next_rr     = '0;
        b_grant_valid = 1'b0;
        BID_MUX       = '0;
        BRESP_MUX     = RESP_OKAY;
        BREADY_S0     = 1'b0;
        BREADY_S1     = 1'b0;
        BREADY_ERR    = 1'b0;

        for (int k = 0; k < NUM_TARGETS; k++) begin
            if (!b_grant_valid) begin
                case ((b_rr_ptr + k[SELECT_WIDTH-1:0]) % NUM_TARGETS)
                    SEL_S0: if (BVALID_S0) begin
                              BID_MUX       = BID_S0;
                              BRESP_MUX     = BRESP_S0;
                              BREADY_S0     = BREADY_DMUX;
                              b_grant_valid = 1'b1;
                              b_next_rr     = SEL_S1;
                            end
                    SEL_S1: if (BVALID_S1) begin
                              BID_MUX       = BID_S1;
                              BRESP_MUX     = BRESP_S1;
                              BREADY_S1     = BREADY_DMUX;
                              b_grant_valid = 1'b1;
                              b_next_rr     = SEL_ERR;
                            end
                    SEL_ERR: if (BVALID_ERR) begin
                              BID_MUX       = BID_ERR;
                              BRESP_MUX     = BRESP_ERR;
                              BREADY_ERR    = BREADY_DMUX;
                              b_grant_valid = 1'b1;
                              b_next_rr     = SEL_S0;
                            end
                    default: ;
                endcase
            end
        end
        BVALID_MUX = b_grant_valid;
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn)
            b_rr_ptr <= '0;
        else if (BVALID_MUX && BREADY_DMUX)
            b_rr_ptr <= b_next_rr;
    end

endmodule