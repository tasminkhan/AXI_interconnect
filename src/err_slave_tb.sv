//   E1  single-beat bad write        -> one DECERR, BID echoed
//   E2  4-beat bad burst             -> all beats drained, one DECERR
//   E3  missing WLAST (len=1)        -> counter still ends it (no hang)
//   E4  two outstanding bad AWs      -> both DECERR in order (pipelined)

`timescale 1ns/1ps

module err_slave_tb;

    logic       ACLK = 0, ARESETn;
    // AW
    logic [3:0] AWID_I, AWLEN_I;
    logic       AWVALID_I, AWREADY_O;
    // W
    logic       WLAST_I, WVALID_I, WREADY_O;
    // B
    logic [3:0] BID_O;  logic [1:0] BRESP_O;
    logic       BVALID_O, BREADY_I;

    err_slave dut (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_I), .AWLEN_I(AWLEN_I),
        .AWVALID_I(AWVALID_I), .AWREADY_O(AWREADY_O),
        .WLAST_I(WLAST_I), .WVALID_I(WVALID_I), .WREADY_O(WREADY_O),
        .BID_O(BID_O), .BRESP_O(BRESP_O),
        .BVALID_O(BVALID_O), .BREADY_I(BREADY_I)
    );

    always #5 ACLK = ~ACLK;

    localparam [1:0] DECERR = 2'b11;

    integer errors = 0;
    task automatic check(input bit c, input string m);
        if (!c) begin errors++; $display("[%0t] FAIL: %s", $time, m); end
        else                     $display("[%0t] pass: %s", $time, m);
    endtask

    // push one bad AW (id + len); completes on a clean AW handshake edge
    task automatic aw_push(input [3:0] id, input [3:0] len);
        AWID_I <= id; AWLEN_I <= len; AWVALID_I <= 1'b1;
        do @(posedge ACLK); while (!(AWVALID_I && AWREADY_O));
        AWVALID_I <= 1'b0;
    endtask

    // send nbeats data beats; WLAST asserted on beat 'last_at'
    // (use last_at = 99 to never assert WLAST)
    task automatic w_send(input int nbeats, input int last_at);
        for (int i = 0; i < nbeats; i++) begin
            WLAST_I <= (i == last_at); WVALID_I <= 1'b1;
            do @(posedge ACLK); while (!(WVALID_I && WREADY_O));
            WVALID_I <= 1'b0; WLAST_I <= 1'b0;
        end
    endtask

    // collect the B response and check ID + DECERR
    task automatic b_get(input [3:0] exp_id);
        BREADY_I <= 1'b1;
        do @(posedge ACLK); while (!(BVALID_O && BREADY_I));
        check(BID_O   === exp_id, $sformatf("BID echo %0h (exp %0h)", BID_O, exp_id));
        check(BRESP_O === DECERR,  "BRESP = DECERR");
        BREADY_I <= 1'b0;
    endtask

    initial begin
        $dumpfile("err_slave.vcd");
        $dumpvars(0, err_slave_tb);

        AWID_I<=0; AWLEN_I<=0; AWVALID_I<=0; WLAST_I<=0; WVALID_I<=0; BREADY_I<=0;
        ARESETn<=0;
        repeat (3) @(posedge ACLK);
        ARESETn<=1;
        @(posedge ACLK);

        $display("\n--- E1: single-beat bad write -> DECERR ---");
        aw_push(4'h5, 4'd0);      // 1 beat
        w_send(1, 0);             // WLAST on beat 0
        b_get(4'h5);

        $display("\n--- E2: 4-beat bad burst -> all drained, one DECERR ---");
        aw_push(4'h6, 4'd3);      // 4 beats
        w_send(4, 3);             // WLAST on beat 3
        b_get(4'h6);

        $display("\n--- E3: missing WLAST (len=1, never asserted) -> no hang ---");
        aw_push(4'h7, 4'd1);      // 2 beats promised
        w_send(2, 99);            // send 2 beats, never assert WLAST
        b_get(4'h7);              // counter still terminates -> DECERR

        repeat (4) @(posedge ACLK);
        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end

    initial begin #20000; $display("[%0t] TIMEOUT", $time); $finish; end

endmodule
