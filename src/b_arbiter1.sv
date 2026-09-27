`timescale 1ns / 1ps
import param_pkg::*;

// Two-target B arbiter (S1 + ERR). Round-robin between the two, BREADY
// demuxed to the granted target. Single-beat responses (no lock).
module b_arbiter1 (
    input  logic ACLK,
    input  logic ARESETn,

    input  logic [ID_WIDTH-1:0]   BID_S1,   BID_ERR,
    input  logic [RESP_WIDTH-1:0] BRESP_S1, BRESP_ERR,
    input  logic                  BVALID_S1, BVALID_ERR,

    output logic BREADY_S1,
    output logic BREADY_ERR,

    output logic [ID_WIDTH-1:0]   BID_MUX,
    output logic [RESP_WIDTH-1:0] BRESP_MUX,
    output logic                  BVALID_MUX,
    input  logic                  BREADY_DMUX
);
    logic       b_rr_ptr, b_next_rr;   // 0 -> prefer S1, 1 -> prefer ERR
    logic       b_grant_valid;

    always_comb begin
        b_next_rr     = b_rr_ptr;
        b_grant_valid = 1'b0;
        BID_MUX       = '0;
        BRESP_MUX     = RESP_OKAY;
        BREADY_S1     = 1'b0;
        BREADY_ERR    = 1'b0;

        for (int k = 0; k < 2; k++) begin
            if (!b_grant_valid) begin
                case ((b_rr_ptr + k[0]) & 1'b1)
                    1'b0: if (BVALID_S1) begin
                              BID_MUX = BID_S1; BRESP_MUX = BRESP_S1;
                              BREADY_S1 = BREADY_DMUX;
                              b_grant_valid = 1'b1; b_next_rr = 1'b1;
                          end
                    1'b1: if (BVALID_ERR) begin
                              BID_MUX = BID_ERR; BRESP_MUX = BRESP_ERR;
                              BREADY_ERR = BREADY_DMUX;
                              b_grant_valid = 1'b1; b_next_rr = 1'b0;
                          end
                    default: ;
                endcase
            end
        end
        BVALID_MUX = b_grant_valid;
    end

    always_ff @(posedge ACLK) begin
        if (!ARESETn)                       b_rr_ptr <= 1'b0;
        else if (BVALID_MUX && BREADY_DMUX) b_rr_ptr <= b_next_rr;
    end
endmodule
