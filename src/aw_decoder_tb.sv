`timescale 1ns / 1ps
//=====================================================================
//   ADDR_STEP        = DATA_WIDTH/8              = 2
//   SLAVE_ADDR_SPAN  = SLAVE_REG_COUNT*ADDR_STEP = 32
//   SLAVE0: 0xA0 .. 0xBF
//   SLAVE1: 0xC0 .. 0xDF
//=====================================================================
import param_pkg::*;

module decoder_tb;

    logic [ADDRESS_WIDTH-1:0] AWADDR_SKD;
    logic [LEN_WIDTH-1:0]     AWLEN_SKD;
    logic [BURST_WIDTH-1:0]   AWBURST_SKD;
    logic [SELECT_WIDTH-1:0]  aw_sel;

    aw_decoder dut (
        .AWADDR_SKD  (AWADDR_SKD),
        .AWLEN_SKD   (AWLEN_SKD),
        .AWBURST_SKD (AWBURST_SKD),
        .aw_sel      (aw_sel)
    );

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input logic [ADDRESS_WIDTH-1:0] addr,
        input logic [LEN_WIDTH-1:0]     len,
        input logic [BURST_WIDTH-1:0]   burst,
        input logic [SELECT_WIDTH-1:0]  expected,
        input string                    name
    );
        AWADDR_SKD  = addr;
        AWLEN_SKD   = len;
        AWBURST_SKD = burst;
        #1; // allow always_comb to settle

        if (aw_sel === expected) begin
            $display("[PASS] %-28s addr=0x%0h len=%0d burst=%0b -> aw_sel=%0d",
                       name, addr, len, burst, aw_sel);
            pass_count++;
        end else begin
            $display("[FAIL] %-28s addr=0x%0h len=%0d burst=%0b -> aw_sel=%0d (expected %0d)",
                       name, addr, len, burst, aw_sel, expected);
            fail_count++;
        end
    endtask

    initial begin
        $display("=== decoder_tb start ===");

        // ---- slave0 window (0xA0 .. 0xBF) ----
        check(8'hA0, 4'd0,  BURST_INCR, SEL_S0,  "S0 single beat, base");
        check(8'hBE, 4'd0,  BURST_INCR, SEL_S0,  "S0 single beat, near top");

        // ---- slave1 window (0xC0 .. 0xDF) ----
        check(8'hC0, 4'd15, BURST_INCR, SEL_S1,  "S1 full-span burst, fits");

        // ---- burst overruns its window -> SEL_ERR ----
        // NOTE: AWLEN_SKD is only LEN_WIDTH(4) bits wide, so the max
        // representable len is 15 - and 15*ADDR_STEP(2)=30 never
        // overruns a 32-byte window from its base. To actually trigger
        // the overrun path we start near the TOP of the window instead.
        check(8'hBE, 4'd1,  BURST_INCR, SEL_ERR, "S0 burst overruns window");

        // ---- unsupported burst type -> SEL_ERR ----
        check(8'hA0, 4'd0,  2'b10,      SEL_ERR, "WRAP burst rejected");

        // ---- unaligned start address -> SEL_ERR ----
        check(8'hA1, 4'd0,  BURST_INCR, SEL_ERR, "unaligned start addr");

        // ---- address outside both windows -> SEL_ERR ----
        check(8'h10, 4'd0,  BURST_INCR, SEL_ERR, "addr below S0 window");
        check(8'hE0, 4'd0,  BURST_INCR, SEL_ERR, "addr just above S1_END");

        $display("=== decoder_tb done: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);

        $finish;
    end

endmodule