`timescale 1ns/1ps
import param_pkg::*;

module b_arbiter_tb;

    logic ACLK = 0, ARESETn;

    logic [ID_WIDTH-1:0]   BID_S0, BID_S1, BID_ERR;
    logic [RESP_WIDTH-1:0] BRESP_S0, BRESP_S1, BRESP_ERR;
    logic                  BVALID_S0, BVALID_S1, BVALID_ERR;
    logic                  BREADY_S0, BREADY_S1, BREADY_ERR;
    logic [ID_WIDTH-1:0]   BID_MUX;
    logic [RESP_WIDTH-1:0] BRESP_MUX;
    logic                  BVALID_MUX, BREADY_DMUX;

    b_arbiter dut (.*);

    always #5 ACLK = ~ACLK;

    int pass_count = 0, fail_count = 0;
    localparam int NONE = -1;

    task automatic drive(input logic v0, v1, verr,
                         input logic [ID_WIDTH-1:0] id0, id1, iderr);
        BVALID_S0 <= v0;   BID_S0 <= id0;   BRESP_S0 <= RESP_OKAY;
        BVALID_S1 <= v1;   BID_S1 <= id1;   BRESP_S1 <= RESP_SLVERR;  // set to SLVERR only to distinguish between responses
        BVALID_ERR<= verr; BID_ERR<= iderr; BRESP_ERR<= RESP_DECERR;
    endtask

    task automatic expect_grant(input int who,
                                input logic [ID_WIDTH-1:0]   exp_id,
                                input logic [RESP_WIDTH-1:0] exp_resp,
                                input string name);
        logic ok, exp_valid, exp_r0, exp_r1, exp_re;
        exp_valid = (who != NONE);
        exp_r0    = (who == 0) & BREADY_DMUX;
        exp_r1    = (who == 1) & BREADY_DMUX;
        exp_re    = (who == 2) & BREADY_DMUX;
        ok = (BVALID_MUX === exp_valid) && (BREADY_S0 === exp_r0)
          && (BREADY_S1 === exp_r1)     && (BREADY_ERR === exp_re)
          && (!exp_valid || (BID_MUX === exp_id && BRESP_MUX === exp_resp));
        if (ok) begin
            $display("[PASS] %-42s valid=%b id=%h resp=%b READYdmux=%b%b%b",
                     name, BVALID_MUX, BID_MUX, BRESP_MUX,
                     BREADY_S0, BREADY_S1, BREADY_ERR);
            pass_count++;
        end else begin
            $display("[FAIL] %-42s valid=%b id=%h resp=%b READYdmux=%b%b%b  (exp valid=%b id=%h resp=%b READYdmux=%b%b%b)",
                     name, BVALID_MUX, BID_MUX, BRESP_MUX,
                     BREADY_S0, BREADY_S1, BREADY_ERR,
                     exp_valid, exp_id, exp_resp, exp_r0, exp_r1, exp_re);
            fail_count++;
        end
    endtask

    initial begin
        $dumpfile("b_arbiter.vcd");
        $dumpvars(0, b_arbiter_tb);
        $display("=== b_arbiter_tb start ===");

        ARESETn     <= 0;
        BREADY_DMUX <= 0;
        drive(0,0,0, '0,'0,'0);
        repeat (2) @(posedge ACLK);
        ARESETn <= 1;

        @(posedge ACLK);
        drive(1,0,0, 4'hA,4'h0,4'h0);
        BREADY_DMUX <= 1;
        @(posedge ACLK);
        expect_grant(0, 4'hA, RESP_OKAY, "T1: S0 only");

        drive(1,1,0, 4'h1,4'h2,4'h0);
        @(posedge ACLK);
        expect_grant(1, 4'h2, RESP_SLVERR, "T2: S0+S1, rr picks S1");

        drive(0,0,1, 4'h0,4'h0,4'hE);
        @(posedge ACLK);
        expect_grant(2, 4'hE, RESP_DECERR, "T3: ERR only");

        drive(0,0,0, '0,'0,'0);
        @(posedge ACLK);
        expect_grant(NONE, 'x, 'x, "T4: idle, no grant");

        BREADY_DMUX <= 0;
        drive(1,0,0, 4'h7,4'h0,4'h0);
        @(posedge ACLK);
        expect_grant(0, 4'h7, RESP_OKAY, "T5: S0 valid, not ready");

        BREADY_DMUX <= 1;
        @(posedge ACLK);
        expect_grant(0, 4'h7, RESP_OKAY, "T5b: S0 still granted after no-accept");

        @(posedge ACLK);
        $display("=== done: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else                 $display("*** %0d TEST(S) FAILED ***", fail_count);
        $finish;
    end

endmodule