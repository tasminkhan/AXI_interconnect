`timescale 1ns/1ps
import param_pkg::*;

module top_seq1_tb;
    logic ACLK=0, ARESETn;
    always #5 ACLK=~ACLK;

    logic [ID_WIDTH-1:0] AWID; logic [ADDRESS_WIDTH-1:0] AWADDR;
    logic [LEN_WIDTH-1:0] AWLEN; logic [BURST_WIDTH-1:0] AWBURST;
    logic AWVALID, AWREADY;
    logic [DATA_WIDTH-1:0] WDATA; logic [STROBE_WIDTH-1:0] WSTRB;
    logic WLAST, WVALID, WREADY;
    logic [ID_WIDTH-1:0] BID; logic [RESP_WIDTH-1:0] BRESP; logic BVALID, BREADY;
    logic [ID_WIDTH-1:0] ARID; logic [ADDRESS_WIDTH-1:0] ARADDR;
    logic [LEN_WIDTH-1:0] ARLEN; logic [BURST_WIDTH-1:0] ARBURST;
    logic [QOS_WIDTH-1:0] ARQOS; logic ARVALID, ARREADY;
    logic [ID_WIDTH-1:0] RID; logic [DATA_WIDTH-1:0] RDATA; logic [RESP_WIDTH-1:0] RRESP;
    logic RLAST, RVALID, RREADY;
    logic [DATA_WIDTH-1:0] rbeats [0:15];

    top_seq1 dut (.*);

    int pass_count=0, fail_count=0;
    task automatic check(input logic c, input string n);
        if (c) begin $display("[PASS] %s", n); pass_count++; end
        else   begin $display("[FAIL] %s", n); fail_count++; end
    endtask
    
    function automatic logic [DATA_WIDTH-1:0] rg1(input int i); 
        return dut.u_slave1.u_regs.regs[i];
    endfunction

    task automatic aw_send(input [ID_WIDTH-1:0] id, input [ADDRESS_WIDTH-1:0] a,
                           input [LEN_WIDTH-1:0] len, input [BURST_WIDTH-1:0] b=BURST_INCR);
        AWID<=id; AWADDR<=a; AWLEN<=len; AWBURST<=b; AWVALID<=1'b1;
        do @(posedge ACLK); while(!(AWVALID&&AWREADY)); AWVALID<=1'b0;
    endtask
    task automatic w_send(input int n, input [DATA_WIDTH-1:0] base,
                          input [STROBE_WIDTH-1:0] strb={STROBE_WIDTH{1'b1}}, input int last_at=-1);
        int lb; lb=(last_at==-1)?n-1:last_at;
        for (int i=0;i<n;i++) begin
            WDATA<=base+i; WSTRB<=strb; WLAST<=(i==lb); WVALID<=1'b1;
            do @(posedge ACLK); while(!(WVALID&&WREADY)); WVALID<=1'b0; WLAST<=1'b0;
        end
    endtask
    task automatic b_get(output logic [ID_WIDTH-1:0] id, output logic [RESP_WIDTH-1:0] r);
        logic done; BREADY<=1'b1; done=1'b0;
        while(!done) begin
            @(negedge ACLK);
            if (BVALID) begin id=BID; r=BRESP; @(posedge ACLK); done=1'b1; end
            else @(posedge ACLK);
        end
        BREADY<=1'b0;
    endtask
    task automatic ar_send(input [ID_WIDTH-1:0] id, input [ADDRESS_WIDTH-1:0] a,
                           input [LEN_WIDTH-1:0] len, input [QOS_WIDTH-1:0] q=4'd0);
        ARID<=id; ARADDR<=a; ARLEN<=len; ARBURST<=BURST_INCR; ARQOS<=q; ARVALID<=1'b1;
        do @(posedge ACLK); while(!(ARVALID&&ARREADY)); ARVALID<=1'b0;
    endtask
    task automatic r_get(input int n, output logic [ID_WIDTH-1:0] id, output logic [RESP_WIDTH-1:0] r);
        logic got; RREADY<=1'b1;
        for (int i=0;i<n;i++) begin
            got=1'b0;
            while(!got) begin @(negedge ACLK); if (RVALID) got=1'b1; else @(posedge ACLK); end
            rbeats[i]=RDATA; id=RID; r=RRESP;
            check(RLAST===(i==n-1), $sformatf("RLAST beat %0d of %0d", i, n-1));
            @(posedge ACLK);
        end
        RREADY<=1'b0;
    endtask

    logic [ID_WIDTH-1:0] gid; logic [RESP_WIDTH-1:0] gr;
    initial begin
        $dumpfile("top_seq1.vcd"); $dumpvars(0, top_seq1_tb);
        AWVALID<=0; WVALID<=0; WLAST<=0; WSTRB<='1; BREADY<=0; ARVALID<=0; RREADY<=0; ARQOS<=0;
        ARESETn<=0; repeat(3)@(posedge ACLK); ARESETn<=1; @(posedge ACLK);

        $display("\n== T1: single write + readback ==");
        aw_send(4'h1, SLAVE1_BASE, 4'd0); w_send(1, 16'h1111); b_get(gid,gr);
        check(gid===4'h1 && gr===RESP_OKAY, "T1 write OKAY, BID echo");
        ar_send(4'h1, SLAVE1_BASE, 4'd0); r_get(1, gid, gr);
        check(gid===4'h1 && rbeats[0]===16'h1111, "T1 readback matches");

        $display("\n== T2: 4-beat burst write + burst read ==");
        aw_send(4'h2, SLAVE1_BASE+8'd8, 4'd3); w_send(4, 16'hB000); b_get(gid,gr);
        check(gr===RESP_OKAY, "T2 burst write OKAY");
        ar_send(4'h2, SLAVE1_BASE+8'd8, 4'd3); r_get(4, gid, gr);
        check(rbeats[0]===16'hB000 && rbeats[3]===16'hB003, "T2 burst read data");

        $display("\n== T3: in-order service (two reads, low then high, no reorder) ==");
        // seq fabric: order of R must equal order of AR
        ar_send(4'h5, SLAVE1_BASE,      4'd0, 4'd1);   // first
        ar_send(4'h6, SLAVE1_BASE+8'd8, 4'd0, 4'd15);  // second, higher QoS - but seq ignores QoS
        r_get(1, gid, gr); check(gid===4'h5, "T3 first R is id5 (issue order)");
        r_get(1, gid, gr); check(gid===4'h6, "T3 second R is id6");

        $display("\n== T4: DECERR read (unmapped) ==");
        ar_send(4'h7, 8'h10, 4'd1); r_get(2, gid, gr);
        check(gr===RESP_DECERR && gid===4'h7, "T4 unmapped -> DECERR, all beats");

        repeat(4)@(posedge ACLK);
        $display("\n== PASS %0d  FAIL %0d ==", pass_count, fail_count);
        if (fail_count==0) $display("*** ALL PASSED ***");
        $finish;
    end
    initial begin #60000; $display("*** TIMEOUT ***"); $finish; end
endmodule
