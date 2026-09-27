`timescale 1ns/1ps
import param_pkg::*;

`ifndef USE_DUT_PORTS
  `define O_AWREADY(m) dut.awready_i[m]
  `define O_WREADY(m)  dut.wready_i[m]
  `define O_BVALID(m)  dut.bvalid_i[m]
  `define O_BID(m)     dut.bid_i[m]
  `define O_BRESP(m)   dut.bresp_i[m]
  `define O_ARREADY(m) dut.arready_i[m]
  `define O_RVALID(m)  dut.rvalid_i[m]
  `define O_RID(m)     dut.rid_i[m]
  `define O_RDATA(m)   dut.rdata_i[m]
  `define O_RRESP(m)   dut.rresp_i[m]
  `define O_RLAST(m)   dut.rlast_i[m]
`else
  `define O_AWREADY(m) AWREADY[m]
  `define O_WREADY(m)  WREADY[m]
  `define O_BVALID(m)  BVALID[m]
  `define O_BID(m)     BID[m]
  `define O_BRESP(m)   BRESP[m]
  `define O_ARREADY(m) ARREADY[m]
  `define O_RVALID(m)  RVALID[m]
  `define O_RID(m)     RID[m]
  `define O_RDATA(m)   RDATA[m]
  `define O_RRESP(m)   RRESP[m]
  `define O_RLAST(m)   RLAST[m]
`endif

module top_tb;

    logic ACLK = 0, ARESETn;
    always #5 ACLK = ~ACLK;

    //---------------- DUT interface (arrays, one entry per master) ----
    logic [ORIG_ID_WIDTH-1:0] AWID   [0:NUM_MASTERS-1];
    logic [ADDRESS_WIDTH-1:0] AWADDR [0:NUM_MASTERS-1];
    logic [LEN_WIDTH-1:0]     AWLEN  [0:NUM_MASTERS-1];
    logic [BURST_WIDTH-1:0]   AWBURST[0:NUM_MASTERS-1];
    logic [QOS_WIDTH-1:0]     AWQOS [0:NUM_MASTERS-1];
    logic                     AWVALID[0:NUM_MASTERS-1];
    logic                     AWREADY[0:NUM_MASTERS-1];

    logic [DATA_WIDTH-1:0]    WDATA  [0:NUM_MASTERS-1];
    logic [STROBE_WIDTH-1:0]  WSTRB  [0:NUM_MASTERS-1];
    logic                     WLAST  [0:NUM_MASTERS-1];
    logic                     WVALID [0:NUM_MASTERS-1];
    logic                     WREADY [0:NUM_MASTERS-1];

    logic [ORIG_ID_WIDTH-1:0] BID    [0:NUM_MASTERS-1];
    logic [RESP_WIDTH-1:0]    BRESP  [0:NUM_MASTERS-1];
    logic                     BVALID [0:NUM_MASTERS-1];
    logic                     BREADY [0:NUM_MASTERS-1];

    logic [ORIG_ID_WIDTH-1:0] ARID   [0:NUM_MASTERS-1];
    logic [ADDRESS_WIDTH-1:0] ARADDR [0:NUM_MASTERS-1];
    logic [LEN_WIDTH-1:0]     ARLEN  [0:NUM_MASTERS-1];
    logic [BURST_WIDTH-1:0]   ARBURST[0:NUM_MASTERS-1];
    logic [QOS_WIDTH-1:0]     ARQOS  [0:NUM_MASTERS-1];
    logic                     ARVALID[0:NUM_MASTERS-1];
    logic                     ARREADY[0:NUM_MASTERS-1];

    logic [ORIG_ID_WIDTH-1:0] RID    [0:NUM_MASTERS-1];
    logic [DATA_WIDTH-1:0]    RDATA  [0:NUM_MASTERS-1];
    logic [RESP_WIDTH-1:0]    RRESP  [0:NUM_MASTERS-1];
    logic                     RLAST  [0:NUM_MASTERS-1];
    logic                     RVALID [0:NUM_MASTERS-1];
    logic                     RREADY [0:NUM_MASTERS-1];

    top dut (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID(AWID), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWBURST(AWBURST), .AWQOS(AWQOS),
        .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST),
        .WVALID(WVALID), .WREADY(WREADY),
        .BID(BID), .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARID(ARID), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARBURST(ARBURST),
        .ARQOS(ARQOS), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RID(RID), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST),
        .RVALID(RVALID), .RREADY(RREADY)
    );

    //---------------- scoreboard --------------------------------------
    int pass_count = 0, fail_count = 0;
    task automatic check(input logic c, input string n);
        if (c) begin $display("[PASS] %s", n); pass_count++; end
        else   begin $display("[FAIL] %s", n); fail_count++; end
    endtask

    // address of register n inside slave s
    function automatic logic [ADDRESS_WIDTH-1:0] slv_addr(input int s, input int n);
        slv_addr = (s == 0 ? SLAVE0_BASE : SLAVE1_BASE) + ADDRESS_WIDTH'(2*n);
    endfunction

    //---------------- concurrency monitors ----------------------------
    logic saw_parallel_w, saw_parallel_ar;
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            saw_parallel_w  <= 1'b0;
            saw_parallel_ar <= 1'b0;
        end else begin
            if (dut.w_arbout_valid[0] && dut.w_arbout_ready[0] &&
                dut.w_arbout_valid[1] && dut.w_arbout_ready[1])
                saw_parallel_w <= 1'b1;
            if (dut.ar_arbout_valid[0] && dut.ar_arbout_ready[0] &&
                dut.ar_arbout_valid[1] && dut.ar_arbout_ready[1])
                saw_parallel_ar <= 1'b1;
        end
    end

    //---------------- per-master BFM tasks ----------------------------

    task automatic aw_send(input int m, input [ORIG_ID_WIDTH-1:0] id,
                           input [ADDRESS_WIDTH-1:0] a, input [LEN_WIDTH-1:0] len);
        AWID[m]    <= id;
        AWADDR[m]  <= a;
        AWLEN[m]   <= len;
        AWBURST[m] <= BURST_INCR;
        AWQOS[m]   <= '0;
        AWVALID[m] <= 1'b1;
        do @(posedge ACLK); while (!(AWVALID[m] && `O_AWREADY(m)));
        AWVALID[m] <= 1'b0;
    endtask

    task automatic w_send(input int m, input int nbeats, input [DATA_WIDTH-1:0] base);
        for (int i = 0; i < nbeats; i++) begin
            WDATA[m]  <= base + DATA_WIDTH'(i);
            WSTRB[m]  <= '1;
            WLAST[m]  <= (i == nbeats-1);
            WVALID[m] <= 1'b1;
            do @(posedge ACLK); while (!(WVALID[m] && `O_WREADY(m)));
            WVALID[m] <= 1'b0;
            WLAST[m]  <= 1'b0;
        end
    endtask

    task automatic b_get(input int m, output logic [ORIG_ID_WIDTH-1:0] id,
                                      output logic [RESP_WIDTH-1:0] rsp);
        logic done;
        BREADY[m] <= 1'b1;
        done = 1'b0;
        while (!done) begin
            @(negedge ACLK);
            if (`O_BVALID(m)) begin
                id   = `O_BID(m);
                rsp  = `O_BRESP(m);
                done = 1'b1;
            end
            @(posedge ACLK);
        end
        BREADY[m] <= 1'b0;
    endtask

    // full single/burst write, returns the B response
    task automatic do_write(input int m, input [ORIG_ID_WIDTH-1:0] id,
                            input [ADDRESS_WIDTH-1:0] a, input int nbeats,
                            input [DATA_WIDTH-1:0] base,
                            output logic [ORIG_ID_WIDTH-1:0] bid,
                            output logic [RESP_WIDTH-1:0] bresp);
        aw_send(m, id, a, LEN_WIDTH'(nbeats-1));
        w_send (m, nbeats, base);
        b_get  (m, bid, bresp);
    endtask

    task automatic ar_send(input int m, input [ORIG_ID_WIDTH-1:0] id,
                           input [ADDRESS_WIDTH-1:0] a, input [LEN_WIDTH-1:0] len);
        ARID[m]    <= id;
        ARADDR[m]  <= a;
        ARLEN[m]   <= len;
        ARBURST[m] <= BURST_INCR;
        ARQOS[m]   <= '0;
        ARVALID[m] <= 1'b1;
        do @(posedge ACLK); while (!(ARVALID[m] && `O_ARREADY(m)));
        ARVALID[m] <= 1'b0;
    endtask

    // capture nbeats of R; beats land in rbeat[m][0..n-1]
    logic [DATA_WIDTH-1:0] rbeat [0:NUM_MASTERS-1][0:15];
    task automatic r_get(input int m, input int nbeats,
                         output logic [ORIG_ID_WIDTH-1:0] id,
                         output logic [RESP_WIDTH-1:0] rsp,
                         output logic last_ok);
        logic got;
        RREADY[m] <= 1'b1;
        last_ok = 1'b1;
        for (int i = 0; i < nbeats; i++) begin
            got = 1'b0;
            while (!got) begin
                @(negedge ACLK);
                if (`O_RVALID(m)) begin
                    rbeat[m][i] = `O_RDATA(m);
                    id          = `O_RID(m);
                    rsp         = `O_RRESP(m);
                    if (`O_RLAST(m) !== (i == nbeats-1)) last_ok = 1'b0;
                    got = 1'b1;
                end
                @(posedge ACLK);
            end
        end
        RREADY[m] <= 1'b0;
    endtask

    task automatic do_read(input int m, input [ORIG_ID_WIDTH-1:0] id,
                           input [ADDRESS_WIDTH-1:0] a, input int nbeats,
                           output logic [ORIG_ID_WIDTH-1:0] rid,
                           output logic [RESP_WIDTH-1:0] rrsp,
                           output logic last_ok);
        ar_send(m, id, a, LEN_WIDTH'(nbeats-1));
        r_get  (m, nbeats, rid, rrsp, last_ok);
    endtask

    //---------------- result holders (avoid racing shared counters) ---
    logic [ORIG_ID_WIDTH-1:0] bid0, bid1, rid0, rid1;
    logic [RESP_WIDTH-1:0]    brsp0, brsp1, rrsp0, rrsp1;
    logic                     lok0, lok1;

    initial begin
        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);

        for (int i = 0; i < NUM_MASTERS; i++) begin
            AWID[i]='0; AWADDR[i]='0; AWLEN[i]='0; AWBURST[i]=BURST_INCR;
            AWQOS[i]='0; AWVALID[i]=1'b0;
            WDATA[i]='0; WSTRB[i]='1; WLAST[i]=1'b0; WVALID[i]=1'b0;
            BREADY[i]=1'b0;
            ARID[i]='0; ARADDR[i]='0; ARLEN[i]='0; ARBURST[i]=BURST_INCR;
            ARQOS[i]='0; ARVALID[i]=1'b0; RREADY[i]=1'b0;
        end
        ARESETn <= 1'b0;
        repeat (4) @(posedge ACLK);
        ARESETn <= 1'b1;
        @(posedge ACLK);

        //--------------------------------------------------------------
        $display("\n== T1: per-master single write + readback ==");
        do_write(0, 3'd1, slv_addr(0,0), 1, 16'hA000, bid0, brsp0);
        check(bid0===3'd1 && brsp0===RESP_OKAY, "T1 M0 write OKAY, BID echoed");
        do_read (0, 3'd1, slv_addr(0,0), 1, rid0, rrsp0, lok0);
        check(rid0===3'd1 && rbeat[0][0]===16'hA000 && lok0,
              "T1 M0 readback A000, RID echoed, RLAST ok");

        do_write(1, 3'd2, slv_addr(1,0), 1, 16'hB000, bid1, brsp1);
        check(bid1===3'd2 && brsp1===RESP_OKAY, "T1 M1 write OKAY, BID echoed");
        do_read (1, 3'd2, slv_addr(1,0), 1, rid1, rrsp1, lok1);
        check(rid1===3'd2 && rbeat[1][0]===16'hB000 && lok1,
              "T1 M1 readback B000, RID echoed, RLAST ok");

        //--------------------------------------------------------------
        $display("\n== T2: both masters -> DIFFERENT slaves, concurrently ==");
        // 4-beat writes launched together; the monitor proves both slave
        // ports accepted W in the same cycle at least once.
        fork
            do_write(0, 3'd1, slv_addr(0,4), 4, 16'h1100, bid0, brsp0);
            do_write(1, 3'd2, slv_addr(1,4), 4, 16'h2200, bid1, brsp1);
        join
        check(brsp0===RESP_OKAY && brsp1===RESP_OKAY, "T2 both writes OKAY");
        check(saw_parallel_w, "T2 both slave W ports active in the same cycle");
        fork
            do_read(0, 3'd1, slv_addr(0,4), 4, rid0, rrsp0, lok0);
            do_read(1, 3'd2, slv_addr(1,4), 4, rid1, rrsp1, lok1);
        join
        check(rbeat[0][0]===16'h1100 && rbeat[0][3]===16'h1103 && lok0,
              "T2 M0 burst data 1100..1103 correct");
        check(rbeat[1][0]===16'h2200 && rbeat[1][3]===16'h2203 && lok1,
              "T2 M1 burst data 2200..2203 correct");

        //--------------------------------------------------------------
        $display("\n== T3: both masters -> the SAME slave (arbiter contention) ==");
        fork
            do_write(0, 3'd3, slv_addr(0,8),  1, 16'hAAAA, bid0, brsp0);
            do_write(1, 3'd3, slv_addr(0,9),  1, 16'h5555, bid1, brsp1);
        join
        check(brsp0===RESP_OKAY && brsp1===RESP_OKAY, "T3 both writes to slave0 OKAY");
        do_read(0, 3'd3, slv_addr(0,8), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'hAAAA, "T3 M0's word at reg8 intact");
        do_read(1, 3'd3, slv_addr(0,9), 1, rid1, rrsp1, lok1);
        check(rbeat[1][0]===16'h5555, "T3 M1's word at reg9 intact (no interference)");

        //--------------------------------------------------------------
        $display("\n== T4: ONE master -> BOTH slaves (W routing interlock) ==");
        // Two writes from M0 with different ids to different slaves; the
        // interlock must keep each burst's data with its own slave.
        do_write(0, 3'd4, slv_addr(0,12), 1, 16'hC0DE, bid0, brsp0);
        do_write(0, 3'd5, slv_addr(1,12), 1, 16'hFEED, bid0, brsp0);
        do_read (0, 3'd4, slv_addr(0,12), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'hC0DE, "T4 slave0 got C0DE");
        do_read (0, 3'd5, slv_addr(1,12), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'hFEED, "T4 slave1 got FEED (data not crossed)");

        //--------------------------------------------------------------
        $display("\n== T5: same ORIGINAL id from both masters (tag isolation) ==");
        fork
            do_write(0, 3'd7, slv_addr(0,2), 1, 16'h1111, bid0, brsp0);
            do_write(1, 3'd7, slv_addr(1,2), 1, 16'h2222, bid1, brsp1);
        join
        check(bid0===3'd7 && bid1===3'd7, "T5 both B responses carry orig id 7");
        do_read(0, 3'd7, slv_addr(0,2), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'h1111 && rid0===3'd7, "T5 M0 id7 -> 1111");
        do_read(1, 3'd7, slv_addr(1,2), 1, rid1, rrsp1, lok1);
        check(rbeat[1][0]===16'h2222 && rid1===3'd7, "T5 M1 id7 -> 2222 (no aliasing)");

        //--------------------------------------------------------------
        $display("\n== T6: err slave (unmapped address) ==");
        do_read(0, 3'd6, 8'h10, 2, rid0, rrsp0, lok0);
        check(rrsp0===RESP_DECERR, "T6 unmapped read -> DECERR");
        check(lok0, "T6 unmapped read returned both beats with RLAST on the last");
        check(rid0===3'd6, "T6 DECERR read echoes the original id");
        do_write(1, 3'd6, 8'h20, 2, 16'hDEAD, bid1, brsp1);
        check(brsp1===RESP_DECERR, "T6 unmapped write -> DECERR on B");
        check(bid1===3'd6, "T6 DECERR write echoes the original id");

        //--------------------------------------------------------------
        $display("\n== T7: multi-beat burst write + burst read ==");
        do_write(1, 3'd1, slv_addr(1,6), 4, 16'h7700, bid1, brsp1);
        check(brsp1===RESP_OKAY, "T7 4-beat write OKAY");
        do_read (1, 3'd1, slv_addr(1,6), 4, rid1, rrsp1, lok1);
        check(rbeat[1][0]===16'h7700 && rbeat[1][1]===16'h7701 &&
              rbeat[1][2]===16'h7702 && rbeat[1][3]===16'h7703,
              "T7 burst read data in order");
        check(lok1, "T7 RLAST only on the final beat");

        //--------------------------------------------------------------
        $display("\n== T8: concurrent BURSTS, both masters, different slaves ==");
        fork
            do_write(0, 3'd2, slv_addr(0,4), 4, 16'h8800, bid0, brsp0);
            do_write(1, 3'd4, slv_addr(1,8), 4, 16'h9900, bid1, brsp1);
        join
        fork
            do_read(0, 3'd2, slv_addr(0,4), 4, rid0, rrsp0, lok0);
            do_read(1, 3'd4, slv_addr(1,8), 4, rid1, rrsp1, lok1);
        join
        check(rbeat[0][3]===16'h8803 && lok0, "T8 M0 concurrent burst intact");
        check(rbeat[1][3]===16'h9903 && lok1, "T8 M1 concurrent burst intact");
        check(saw_parallel_ar, "T8 both slave AR ports accepted in the same cycle");

        //--------------------------------------------------------------
        $display("\n== T9: back-to-back writes, one master, same slave ==");
        do_write(0, 3'd1, slv_addr(0,1), 1, 16'h0101, bid0, brsp0);
        do_write(0, 3'd2, slv_addr(0,3), 1, 16'h0303, bid0, brsp0);
        do_read (0, 3'd1, slv_addr(0,1), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'h0101, "T9 first write landed at reg1");
        do_read (0, 3'd2, slv_addr(0,3), 1, rid0, rrsp0, lok0);
        check(rbeat[0][0]===16'h0303, "T9 second write landed at reg3");

        repeat (6) @(posedge ACLK);
        $display("\n===============================================");
        $display("  PASS %0d   FAIL %0d", pass_count, fail_count);
        if (fail_count == 0) $display("  *** ALL TESTS PASSED ***");
        else                 $display("  *** %0d TEST(S) FAILED ***", fail_count);
        $display("===============================================");
        $finish;
    end

    initial begin
        #2000000;
        $display("*** TIMEOUT ***");
        $finish;
    end

endmodule
