//   T1  single-beat write, OKAY, BID echo, data stored
//   T2  4-beat INCR burst, OKAY, all four regs stored
//   T3  WSTRB partial write (lower byte only)
//   T4  outstanding: two AWs pushed into the AW FIFO before any W data,
//       then both bursts' data, responses in order
//   T5  WLAST EARLY: AWLEN says 4 beats, master asserts WLAST on beat 2
//       -> expect SLVERR (the mismatch check)
//   T6  WLAST MISSING / LATE: AWLEN says 2 beats, master never asserts
//       WLAST; counter still terminates at beat==len -> expect SLVERR
//       (burst still ends - no hang - but flagged)

`timescale 1ns/1ps

module slave_tb;

    logic        ACLK = 0, ARESETn;

    // AW
    logic [3:0]  AWID_I;
    logic [7:0]  AWADDR_I;
    logic [3:0]  AWLEN_I;
    logic        AWVALID_I;
    logic        AWREADY_O;
    // W
    logic [15:0] WDATA_I;
    logic [1:0]  WSTRB_I;
    logic        WLAST_I;
    logic        WVALID_I;
    logic        WREADY_O;
    // B
    logic [3:0]  BID_O;
    logic [1:0]  BRESP_O;
    logic        BVALID_O;
    logic        BREADY_I;
    
    // 16 debug register observation ports
    logic [15:0] dbg_reg [0:15];
    
    slave #(.BASE_ADDR(8'hA0)) dut (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_I), .AWADDR_I(AWADDR_I), .AWLEN_I(AWLEN_I),
        .AWVALID_I(AWVALID_I), .AWREADY_O(AWREADY_O),
        .WDATA_I(WDATA_I), .WSTRB_I(WSTRB_I), .WLAST_I(WLAST_I),
        .WVALID_I(WVALID_I), .WREADY_O(WREADY_O),
        .BID_O(BID_O), .BRESP_O(BRESP_O), .BVALID_O(BVALID_O), .BREADY_I(BREADY_I),
        .dbg_reg0 (dbg_reg[0]),  .dbg_reg1 (dbg_reg[1]),
        .dbg_reg2 (dbg_reg[2]),  .dbg_reg3 (dbg_reg[3]),
        .dbg_reg4 (dbg_reg[4]),  .dbg_reg5 (dbg_reg[5]),
        .dbg_reg6 (dbg_reg[6]),  .dbg_reg7 (dbg_reg[7]),
        .dbg_reg8 (dbg_reg[8]),  .dbg_reg9 (dbg_reg[9]),
        .dbg_reg10(dbg_reg[10]), .dbg_reg11(dbg_reg[11]),
        .dbg_reg12(dbg_reg[12]), .dbg_reg13(dbg_reg[13]),
        .dbg_reg14(dbg_reg[14]), .dbg_reg15(dbg_reg[15])
    );

    always #5 ACLK = ~ACLK;

    // response codes (mirror axi_params.svh)
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10, DECERR = 2'b11;

    integer errors = 0;
    task automatic check(input bit c, input string m);
        if (!c) begin errors++; $display("[%0t] FAIL: %s", $time, m); end
        else                     $display("[%0t] pass: %s", $time, m);
    endtask

    // peek a register
    function logic [15:0] rg(input int i); return dut.regs[i]; endfunction

    //==================================================================
    // BFM: push one AW (address only). Waits for AWREADY, holds one
    // cycle, releases. Non-blocking stimulus.
    //==================================================================
    task automatic aw_push(input [3:0] id, input [7:0] addr, input [3:0] len);
        @(posedge ACLK);
        AWID_I    <= id;
        AWADDR_I  <= addr;
        AWLEN_I   <= len;
        AWVALID_I <= 1'b1;
        // hold until the edge where AWVALID & AWREADY are both high
        do @(posedge ACLK); while (!AWREADY_O);
        AWVALID_I <= 1'b0;
    endtask

    //==================================================================
    // BFM: send data beats. 'nbeats' beats sent; 'last_at' is the beat
    // index (0-based) on which WLAST is asserted (set to a huge number
    // to NEVER assert WLAST). Data = base_val + beat.
    //==================================================================
    task automatic w_send(input int nbeats,
                          input [15:0] base_val,
                          input [1:0]  strb,
                          input int    last_at);
        for (int i = 0; i < nbeats; i++) begin
            @(posedge ACLK);
            WDATA_I  <= base_val + i;
            WSTRB_I  <= strb;
            WLAST_I  <= (i == last_at);
            WVALID_I <= 1'b1;
            do @(posedge ACLK); while (!WREADY_O);
            WVALID_I <= 1'b0;
            WLAST_I  <= 1'b0;
        end
    endtask

    //==================================================================
    // BFM: collect the B response.
    //==================================================================
    task automatic b_get(input [3:0] exp_id, output [1:0] resp);
        BREADY_I <= 1'b1;
        do @(posedge ACLK); while (!BVALID_O);
        resp = BRESP_O;
        check(BID_O === exp_id,
              $sformatf("BID echo got %0h exp %0h", BID_O, exp_id));
        BREADY_I <= 1'b0;
    endtask

    logic [1:0] resp;

    initial begin
        $dumpfile("slave.vcd");
        $dumpvars(0, slave_tb);

        AWID_I<=0; AWADDR_I<=0; AWLEN_I<=0; AWVALID_I<=0;
        WDATA_I<=0; WSTRB_I<=2'b11; WLAST_I<=0; WVALID_I<=0; BREADY_I<=0;
        ARESETn<=0;
        repeat (3) @(posedge ACLK);
        ARESETn<=1;
        @(posedge ACLK);

        //------------------------------------------------------------
        $display("\n--- T1: single-beat write @0xA0 (reg0) ---");
        aw_push(4'h0, 8'hA0, 4'd0);
        w_send(1, 16'h1111, 2'b11, 0);          // WLAST on beat 0
        b_get(4'h0, resp);
        check(resp === OKAY,        "T1 BRESP OKAY");
        check(rg(0) === 16'h1111,   "T1 reg0 = 0x1111");

        //------------------------------------------------------------
        $display("\n--- T2: 4-beat burst @0xA8 (regs 4..7) ---");
        aw_push(4'h1, 8'hA8, 4'd3);
        w_send(4, 16'h1000, 2'b11, 3);          // beats 0x1000..0x1003, WLAST on beat 3
        b_get(4'h1, resp);
        check(resp === OKAY, "T2 BRESP OKAY");
        check(rg(4)===16'h1000 && rg(5)===16'h1001 &&
              rg(6)===16'h1002 && rg(7)===16'h1003, "T2 regs4..7 stored");

        //------------------------------------------------------------
        $display("\n--- T3: WSTRB=01 partial write @0xA0 (reg0) ---");
        // reg0 is 0x1111; write 0x00FF lower byte only -> 0x11FF
        aw_push(4'h2, 8'hA0, 4'd0);
        w_send(1, 16'h00FF, 2'b01, 0);
        b_get(4'h2, resp);
        check(resp === OKAY,      "T3 BRESP OKAY");
        check(rg(0) === 16'h11FF, "T3 lower byte written, upper preserved");

        //------------------------------------------------------------
        $display("\n--- T4: two outstanding AWs before any W data ---");
        aw_push(4'h3, 8'hA4, 4'd1);             // txn A -> regs 2..3
        aw_push(4'h4, 8'hAC, 4'd1);             // txn B -> regs 6..7
        // FIFO now holds both; send data in AW order
        w_send(2, 16'h2000, 2'b11, 1);          // txn A data
        b_get(4'h3, resp);
        check(resp === OKAY, "T4 first resp OKAY (id3)");
        w_send(2, 16'h3000, 2'b11, 1);          // txn B data
        b_get(4'h4, resp);
        check(resp === OKAY, "T4 second resp OKAY (id4)");
        check(rg(2)===16'h2000 && rg(3)===16'h2001, "T4 txn A regs2..3");
        check(rg(6)===16'h3000 && rg(7)===16'h3001, "T4 txn B regs6..7");

        //------------------------------------------------------------
        $display("\n--- T5: WLAST EARLY (AWLEN=3 but WLAST on beat 1) -> SLVERR ---");
        aw_push(4'h5, 8'hA0, 4'd3);             // promises 4 beats
        w_send(2, 16'h4000, 2'b11, 1);          // only 2 beats, WLAST on beat 1 (early)
        b_get(4'h5, resp);
        check(resp === SLVERR, "T5 BRESP SLVERR (WLAST asserted early)");

        //------------------------------------------------------------
        $display("\n--- T6: WLAST MISSING (AWLEN=1, never assert WLAST) -> SLVERR ---");
        aw_push(4'h6, 8'hA0, 4'd1);             // promises 2 beats
        w_send(2, 16'h5000, 2'b11, 99);         // 2 beats, WLAST never asserted
        b_get(4'h6, resp);
        check(resp === SLVERR, "T6 BRESP SLVERR (WLAST missing on final beat)");
        // counter still terminated the burst (no hang) - reaching here proves it

        //------------------------------------------------------------
        repeat (4) @(posedge ACLK);
        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule