`timescale 1ns/1ps
import param_pkg::*;

module top_tb;

    logic ACLK = 0, ARESETn;
    always #5 ACLK = ~ACLK;

    logic [ID_WIDTH-1:0]      AWID;
    logic [ADDRESS_WIDTH-1:0] AWADDR;
    logic [LEN_WIDTH-1:0]     AWLEN;
    logic [BURST_WIDTH-1:0]   AWBURST;
    logic                     AWVALID, AWREADY;

    logic [DATA_WIDTH-1:0]    WDATA;
    logic [STROBE_WIDTH-1:0]  WSTRB;
    logic                     WLAST, WVALID, WREADY;

    logic [ID_WIDTH-1:0]      BID;
    logic [RESP_WIDTH-1:0]    BRESP;
    logic                     BVALID, BREADY;

    logic [ID_WIDTH-1:0]      ARID;
    logic [ADDRESS_WIDTH-1:0] ARADDR;
    logic [LEN_WIDTH-1:0]     ARLEN;
    logic [BURST_WIDTH-1:0]   ARBURST;
    logic [QOS_WIDTH-1:0]     ARQOS;
    logic                     ARVALID, ARREADY;

    logic [ID_WIDTH-1:0]      RID;
    logic [DATA_WIDTH-1:0]    RDATA;
    logic [RESP_WIDTH-1:0]    RRESP;
    logic                     RLAST, RVALID, RREADY;

    logic [DATA_WIDTH-1:0]    rbeats [0:15];   // capture buffer for R beats

    top dut (.*);

    int pass_count = 0, fail_count = 0;

    task automatic check(input logic cond, input string name);
        if (cond) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    // read a slave register (dbg_regs carries the same data on a port)
    function automatic logic [DATA_WIDTH-1:0] rg0(input int i);
        return dut.u_slave0.u_regs.regs[i];
    endfunction
    function automatic logic [DATA_WIDTH-1:0] rg1(input int i);
        return dut.u_slave1.u_regs.regs[i];
    endfunction

    //==================================================================
    // BFM tasks. All stimulus is non-blocking on the posedge, and every
    // handshake completes on an edge where VALID & READY are both high.
    //==================================================================
    task automatic aw_send(input [ID_WIDTH-1:0] id,
                           input [ADDRESS_WIDTH-1:0] addr,
                           input [LEN_WIDTH-1:0] len,
                           input [BURST_WIDTH-1:0] burst = BURST_INCR);
        AWID <= id; AWADDR <= addr; AWLEN <= len; AWBURST <= burst;
        AWVALID <= 1'b1;
        do @(posedge ACLK); while (!(AWVALID && AWREADY));
        AWVALID <= 1'b0;
    endtask

    // send nbeats beats of data starting at base_val;
    // WLAST asserted on beat index last_at (use 99 to never assert it)
    task automatic w_send(input int nbeats,
                          input [DATA_WIDTH-1:0] base_val,
                          input [STROBE_WIDTH-1:0] strb = {STROBE_WIDTH{1'b1}},
                          input int last_at = -1);
        int lastbeat;
        lastbeat = (last_at == -1) ? nbeats-1 : last_at;
        for (int i = 0; i < nbeats; i++) begin
            WDATA <= base_val + i; WSTRB <= strb;
            WLAST <= (i == lastbeat); WVALID <= 1'b1;
            do @(posedge ACLK); while (!(WVALID && WREADY));
            WVALID <= 1'b0; WLAST <= 1'b0;
        end
    endtask

    task automatic b_get(output [ID_WIDTH-1:0] id, output [RESP_WIDTH-1:0] resp);
        BREADY <= 1'b1;
        do @(posedge ACLK); while (!(BVALID && BREADY));
        id = BID; resp = BRESP;
        BREADY <= 1'b0;
    endtask

    task automatic ar_send(input [ID_WIDTH-1:0] id,
                           input [ADDRESS_WIDTH-1:0] addr,
                           input [LEN_WIDTH-1:0] len,
                           input [BURST_WIDTH-1:0] burst = BURST_INCR);
        ARID <= id; ARADDR <= addr; ARLEN <= len; ARBURST <= burst;
        ARVALID <= 1'b1;
        do @(posedge ACLK); while (!(ARVALID && ARREADY));
        ARVALID <= 1'b0;
    endtask

    // Collect nbeats R beats into rbeats[], return last id/resp, and
    // check RLAST lands exactly on the final beat (burst-lock correctness).
    task automatic r_get(input int nbeats,
                         output logic [ID_WIDTH-1:0] id,
                         output logic [RESP_WIDTH-1:0] resp);
        RREADY <= 1'b1;
        for (int i = 0; i < nbeats; i++) begin
            do @(posedge ACLK); while (!(RVALID && RREADY));
            rbeats[i] = RDATA; id = RID; resp = RRESP;
            check(RLAST === (i == nbeats-1),
                  $sformatf("R RLAST beat %0d of %0d", i, nbeats-1));
        end
        RREADY <= 1'b0;
    endtask

    // one complete single-beat write
    task automatic write1(input [ID_WIDTH-1:0] id,
                          input [ADDRESS_WIDTH-1:0] addr,
                          input [DATA_WIDTH-1:0] data,
                          output [RESP_WIDTH-1:0] resp);
        logic [ID_WIDTH-1:0] gid;
        aw_send(id, addr, 4'd0);
        w_send(1, data);
        b_get(gid, resp);
        check(gid === id, $sformatf("BID echo %0h", id));
    endtask

    logic [ID_WIDTH-1:0]   gid;
    logic [RESP_WIDTH-1:0] gresp;

    initial begin
        $dumpfile("top.vcd");
        $dumpvars(0, top_tb);

        AWID<='0; AWADDR<='0; AWLEN<='0; AWBURST<=BURST_INCR; AWVALID<=1'b0;
        WDATA<='0; WSTRB<='1; WLAST<=1'b0; WVALID<=1'b0; BREADY<=1'b0;
        ARID<='0; ARADDR<='0; ARLEN<='0; ARBURST<=BURST_INCR; ARVALID<=1'b0;
        RREADY<=1'b0;
        ARESETn <= 1'b0;
        repeat (3) @(posedge ACLK);
        ARESETn <= 1'b1;
        @(posedge ACLK);

        $display("\n===== T1: single-beat writes to both slaves =====");
        write1(4'h1, SLAVE0_BASE,      16'hAAAA, gresp);
        check(gresp === RESP_OKAY,        "T1 slave0 OKAY");
        check(rg0(0) === 16'hAAAA,        "T1 slave0 reg0 = AAAA");

        write1(4'h2, SLAVE1_BASE + 8'd4, 16'hBBBB, gresp);
        check(gresp === RESP_OKAY,        "T1 slave1 OKAY");
        check(rg1(2) === 16'hBBBB,        "T1 slave1 reg2 = BBBB");

        $display("\n===== T2: 4-beat INCR burst =====");
        aw_send(4'h3, SLAVE0_BASE + 8'd8, 4'd5);   // regs 4..7
        w_send(6, 16'h1000);
        b_get(gid, gresp);
        check(gid === 4'h3 && gresp === RESP_OKAY, "T2 burst OKAY, BID echoed");
        check(rg0(4)===16'h1000 && rg0(5)===16'h1001 &&
              rg0(6)===16'h1002 && rg0(7)===16'h1003, "T2 regs 4..7 stored");

        $display("\n===== T3: WSTRB partial write =====");
        // reg0 holds AAAA; write 00FF with strobe 01 -> AAFF
        aw_send(4'h4, SLAVE0_BASE, 4'd0);
        w_send(1, 16'h00FF, 2'b01);
        b_get(gid, gresp);
        check(gresp === RESP_OKAY,  "T3 OKAY");
        check(rg0(0) === 16'hAAFF,  "T3 low byte written, high byte kept");

        $display("\n===== T4: two outstanding AWs before any data =====");
        aw_send(4'h5, SLAVE0_BASE + 8'd16, 4'd1);   // regs 8..9
        aw_send(4'h6, SLAVE0_BASE + 8'd20, 4'd1);   // regs 10..11
        w_send(2, 16'h2000);                        // first burst's data
        b_get(gid, gresp);
        check(gid === 4'h5 && gresp === RESP_OKAY, "T4 first response (id5)");
        w_send(2, 16'h3000);                        // second burst's data
        b_get(gid, gresp);
        check(gid === 4'h6 && gresp === RESP_OKAY, "T4 second response (id6)");
        check(rg0(8)===16'h2000 && rg0(9)===16'h2001,   "T4 regs 8..9");
        check(rg0(10)===16'h3000 && rg0(11)===16'h3001, "T4 regs 10..11");

        $display("\n===== T5: DECERR paths =====");
        // unmapped address
        write1(4'h7, 8'h50, 16'hDEAD, gresp);
        check(gresp === RESP_DECERR, "T5 unmapped 0x50 -> DECERR");
        // just past the top of the map
        write1(4'h8, SLAVE1_END + 8'd1, 16'hDEAD, gresp);
        check(gresp === RESP_DECERR, "T5 above map top -> DECERR");
        // unaligned start
        write1(4'h9, SLAVE0_BASE + 8'd1, 16'hDEAD, gresp);
        check(gresp === RESP_DECERR, "T5 unaligned -> DECERR");
        // unsupported burst type (FIXED)
        aw_send(4'hA, SLAVE0_BASE, 4'd0, 2'b00);
        w_send(1, 16'hDEAD);
        b_get(gid, gresp);
        check(gresp === RESP_DECERR, "T5 FIXED burst -> DECERR");
        // burst that overflows the window end
        aw_send(4'hB, SLAVE0_END - 8'd1, 4'd3);
        w_send(4, 16'hDEAD);
        b_get(gid, gresp);
        check(gresp === RESP_DECERR, "T5 window overflow -> DECERR");

        $display("\n===== T6: errored writes did not corrupt registers =====");
        check(rg0(0) === 16'hAAFF, "T6 slave0 reg0 untouched by DECERRs");
        check(rg1(2) === 16'hBBBB, "T6 slave1 reg2 untouched by DECERRs");

        $display("\n===== T7: interleaved traffic to both slaves =====");
        aw_send(4'hC, SLAVE0_BASE + 8'd24, 4'd0);   // slave0 reg12
        aw_send(4'hD, SLAVE1_BASE + 8'd24, 4'd0);   // slave1 reg12
        w_send(1, 16'h5555);                        // first burst -> slave0
        w_send(1, 16'h6666);                        // second burst -> slave1
        b_get(gid, gresp);
        check(gresp === RESP_OKAY, "T7 first response OKAY");
        b_get(gid, gresp);
        check(gresp === RESP_OKAY, "T7 second response OKAY");
        check(rg0(12) === 16'h5555, "T7 slave0 reg12 = 5555");
        check(rg1(12) === 16'h6666, "T7 slave1 reg12 = 6666");

        $display("\n===== T8: WLAST mismatch -> SLVERR, no hang =====");
        // AWLEN promises 2 beats; send 2 beats but never assert WLAST.
        // The fabric terminates by count, the slave reports SLVERR.
        aw_send(4'hE, SLAVE0_BASE + 8'd28, 4'd1);   // regs 14..15
        w_send(2, 16'h7000, {STROBE_WIDTH{1'b1}}, 99);                // WLAST never asserted
        b_get(gid, gresp);
        check(gid === 4'hE,            "T8 BID echoed on mismatch");
        check(gresp === RESP_SLVERR,   "T8 missing WLAST -> SLVERR (no hang)");
        
        $display("\n===== T14: dipless burst write (AW->W gap lets slave reach W_BURST) =====");
        // Same 4-beat burst as T2, but we let the slave pop the AW and
        // enter W_BURST *before* the first W beat arrives. WREADY is then
        // already high when data streams, so the skid never fills and
        // WREADY holds high for the whole burst - no startup dip.
        aw_send(4'hF, SLAVE0_BASE + 8'd8, 4'd3);   // regs 4..7
        @(posedge ACLK);                            // <-- the one-cycle gap: slave reaches W_BURST here
        w_send(4, 16'hC000);                        // stream unchanged after the gap
        b_get(gid, gresp);
        check(gid === 4'hF && gresp === RESP_OKAY,  "T14 dipless burst OKAY, BID echoed");
        check(rg0(4)===16'hC000 && rg0(5)===16'hC001 &&
              rg0(6)===16'hC002 && rg0(7)===16'hC003, "T14 regs 4..7 stored");
              
        $display("\n===== T10: single-beat read-back from slave0 =====");
        write1(4'h1, SLAVE0_BASE, 16'h1234, gresp);      // reg0 <- 1234
        ar_send(4'h1, SLAVE0_BASE, 4'd0);
        r_get(1, gid, gresp);
        check(gid === 4'h1,           "T10 RID echoes ARID");
        check(gresp === RESP_OKAY,    "T10 RRESP OKAY");
        check(rbeats[0] === 16'h1234, "T10 RDATA reads back the write");

        $display("\n===== T11: 4-beat burst read from slave0 =====");
        aw_send(4'h2, SLAVE0_BASE + 8'd8, 4'd3);          // regs 4..7
        w_send(4, 16'hA000);
        b_get(gid, gresp);
        ar_send(4'h2, SLAVE0_BASE + 8'd8, 4'd3);
        r_get(4, gid, gresp);
        check(gid === 4'h2,        "T11 RID echoed on burst read");
        check(gresp === RESP_OKAY, "T11 burst read OKAY");
        check(rbeats[0]===16'hA000 && rbeats[1]===16'hA001 &&
              rbeats[2]===16'hA002 && rbeats[3]===16'hA003,
              "T11 all four beats correct");

        $display("\n===== T12: read from slave1 (RID routing) =====");
        write1(4'h3, SLAVE1_BASE + 8'd4, 16'h55AA, gresp); // slave1 reg2
        ar_send(4'h3, SLAVE1_BASE + 8'd4, 4'd0);
        r_get(1, gid, gresp);
        check(gid === 4'h3,           "T12 RID echoes for slave1 read");
        check(rbeats[0] === 16'h55AA, "T12 slave1 read data correct");

        $display("\n===== T13: DECERR read (unmapped) returns all beats =====");
        ar_send(4'h4, 8'h50, 4'd3);                        // 4-beat read, unmapped
        r_get(4, gid, gresp);
        check(gresp === RESP_DECERR, "T13 unmapped read -> DECERR");
        check(gid === 4'h4,          "T13 RID echoed on error read");

        // The ID stall acts on the FABRIC-side issue handshake
        // (AWVALID_DMUX & AWREADY_MUX), not on the TB-facing AWREADY
        // (which is only the skid buffer's input-ready). So these tests
        // observe the internal issue point via hierarchical peek, the
        // same style the register checks already use.
        $display("\n===== T15: same-ID write is blocked until prior B clears =====");
        begin : t15
            int issue_seen;

            // First AW (id 7), no data yet -> B cannot return, id 7 stays busy.
            aw_send(4'h7, SLAVE0_BASE + 8'd8, 4'd0);   // reg4

            // Queue a SECOND AW with the same id 7 into the skid buffer.
            // It will be accepted by the skid (AWREADY high) but must NOT
            // be issued to the fabric while id 7 is outstanding.
            aw_send(4'h7, SLAVE0_BASE + 8'd12, 4'd0);  // reg6, sits at skid output

            // Watch the internal issue handshake: it must stay blocked.
            issue_seen = 0;
            repeat (6) begin
                @(posedge ACLK);
                if (dut.AWVALID_DMUX && dut.AWREADY_MUX) issue_seen++;
            end
            check(issue_seen == 0,
                  "T15 second same-id AW not issued to fabric while id busy");

            // Clear the first transaction: send its W beat and take B.
            w_send(1, 16'h7A7A);
            b_get(gid, gresp);
            check(gid === 4'h7 && gresp === RESP_OKAY, "T15 first id7 B returns");

            // id 7 now free -> the parked second AW completes normally.
            w_send(1, 16'h7B7B);
            b_get(gid, gresp);
            check(gid === 4'h7 && gresp === RESP_OKAY, "T15 second id7 B returns");
            check(rg0(4) === 16'h7A7A, "T15 first write landed (reg4)");
            check(rg0(6) === 16'h7B7B, "T15 second write landed (reg6)");
        end

        $display("\n===== T16: different IDs are NOT blocked =====");
        begin : t16
            // First AW id 1, no data -> id 1 busy.
            aw_send(4'h1, SLAVE0_BASE + 8'd16, 4'd0);   // reg8
            // Second AW with a DIFFERENT id (2): aw_send blocks until it is
            // actually accepted, so completing without hanging IS the proof
            // it was not stalled. (A blocked AW would hang here and hit the
            // global timeout.)
            aw_send(4'h2, SLAVE0_BASE + 8'd20, 4'd0);   // reg10
            check(1'b1, "T16 different-id AW accepted while other id busy");
            // Drain both in FIFO order (both to slave0): id1 then id2.
            w_send(1, 16'h1A1A);
            b_get(gid, gresp);
            check(gid === 4'h1, "T16 first B is id1");
            w_send(1, 16'h2B2B);
            b_get(gid, gresp);
            check(gid === 4'h2, "T16 second B is id2");
        end

        $display("\n===== T9: reset clears the register files =====");
        ARESETn <= 1'b0;
        repeat (2) @(posedge ACLK);
        ARESETn <= 1'b1;
        repeat (2) @(posedge ACLK);
        check(rg0(0) === '0 && rg0(7) === '0, "T9 slave0 cleared");
        check(rg1(2) === '0 && rg1(12) === '0, "T9 slave1 cleared");

        repeat (4) @(posedge ACLK);
        $display("\n=====================================");
        $display("  PASS: %0d   FAIL: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("  *** ALL TESTS PASSED ***");
        else                 $display("  *** %0d TEST(S) FAILED ***", fail_count);
        $display("=====================================");
        $finish;
    end

    initial begin
        #100000;
        $display("*** TIMEOUT - design hung ***");
        $finish;
    end

endmodule