// TRAFFIC
//   All masters read from SLAVE 0 so they contend at one arbiter.
//   Each master keeps up to 4 reads outstanding, one per ORIG_ID.
//   (top.sv holds one outstanding transaction per tagged id, and
//   ORIG_ID_WIDTH = 2, so 4 ids = 4 outstanding per master.)
//=====================================================================

`timescale 1ns/1ps
import param_pkg::*;

module traffic_tb;

    localparam int NM  = NUM_MASTERS;            // 3
    localparam int NID = 1 << ORIG_ID_WIDTH;     // 4 ids => 4 outstanding

    int WARMUP  = 200;
    int MEASURE = 800;

    logic ACLK = 0, ARESETn;
    always #5 ACLK = ~ACLK;                       // 10 ns period

    //---------------- DUT interface ----------------------------------
    logic [ORIG_ID_WIDTH-1:0] AWID   [0:NM-1];
    logic [ADDRESS_WIDTH-1:0] AWADDR [0:NM-1];
    logic [LEN_WIDTH-1:0]     AWLEN  [0:NM-1];
    logic [BURST_WIDTH-1:0]   AWBURST[0:NM-1];
    logic [QOS_WIDTH-1:0]     AWQOS  [0:NM-1];
    logic                     AWVALID[0:NM-1];
    logic                     AWREADY[0:NM-1];

    logic [DATA_WIDTH-1:0]    WDATA  [0:NM-1];
    logic [STROBE_WIDTH-1:0]  WSTRB  [0:NM-1];
    logic                     WLAST  [0:NM-1];
    logic                     WVALID [0:NM-1];
    logic                     WREADY [0:NM-1];

    logic [ORIG_ID_WIDTH-1:0] BID    [0:NM-1];
    logic [RESP_WIDTH-1:0]    BRESP  [0:NM-1];
    logic                     BVALID [0:NM-1];
    logic                     BREADY [0:NM-1];

    logic [ORIG_ID_WIDTH-1:0] ARID   [0:NM-1];
    logic [ADDRESS_WIDTH-1:0] ARADDR [0:NM-1];
    logic [LEN_WIDTH-1:0]     ARLEN  [0:NM-1];
    logic [BURST_WIDTH-1:0]   ARBURST[0:NM-1];
    logic [QOS_WIDTH-1:0]     ARQOS  [0:NM-1];
    logic                     ARVALID[0:NM-1];
    logic                     ARREADY[0:NM-1];

    logic [ORIG_ID_WIDTH-1:0] RID    [0:NM-1];
    logic [DATA_WIDTH-1:0]    RDATA  [0:NM-1];
    logic [RESP_WIDTH-1:0]    RRESP  [0:NM-1];
    logic                     RLAST  [0:NM-1];
    logic                     RVALID [0:NM-1];
    logic                     RREADY [0:NM-1];

    top dut (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID(AWID), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWBURST(AWBURST),
        .AWQOS(AWQOS), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST),
        .WVALID(WVALID), .WREADY(WREADY),
        .BID(BID), .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARID(ARID), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARBURST(ARBURST),
        .ARQOS(ARQOS), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RID(RID), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST),
        .RVALID(RVALID), .RREADY(RREADY)
    );

    //---------------- run configuration ------------------------------
    int    CASE_ID = 4;
    int    LOAD    = 100;                 // offered load, percent
    string SCHEME  = "RR";

    int len_cfg  [0:NM-1];
    int qos_cfg  [0:NM-1];
    int load_cfg [0:NM-1];   // per-master offered load; overrides global LOAD

    //  CASE 1  QoS FIGURE. m0 is the urgent master (short bursts,
    //          QOS=15); m1 and m2 are the bulk pair (1 beat vs 16 beats,
    //          equal weight, QOS=0).
    //  CASE 2  BANDWIDTH FIGURE. m0 silent for m1:m2 beat ratio: 
    //=============================================================================

    task automatic apply_case(input int c);
        case (c)
            1: begin        // QoS figure: pixel + bulk pair, all active
                len_cfg  = '{ 3,  0, 15};
                qos_cfg  = '{15,  0,  0};
                load_cfg = '{1,LOAD,LOAD};
            end
            default: begin  // 2: bandwidth figure, m0 removed
                len_cfg  = '{ 3,  0, 15};
                qos_cfg  = '{ 0,  0,  0};
                load_cfg = '{   0,LOAD,LOAD};
            end
        endcase
    endtask

    //---------------- measurement state ------------------------------
    int unsigned cycle;
    bit          counting;

    bit          id_busy   [0:NM-1][0:NID-1];   // id outstanding?
    int unsigned offer_cyc [0:NM-1][0:NID-1];   // ARVALID raised  (queue start)
    int unsigned issue_cyc [0:NM-1][0:NID-1];   // AR handshake    (service start)

    int unsigned beats  [0:NM-1];               // R beats accepted
    int unsigned txns   [0:NM-1];               // completed reads
    longint unsigned sumtot [0:NM-1];           // sum of OFFER->RLAST
    longint unsigned sumsrv [0:NM-1];           // sum of HANDSHAKE->RLAST
    int unsigned maxtot [0:NM-1];
    int unsigned credit [0:NM-1];               // Bresenham load credit

    // Latency histogram, 4 cycles per bin, top bin saturates. Used only
    // to recover a tail percentile: means barely move between arms, the
    // tail is where a priority scheme actually shows up.
    localparam int NBIN    = 128;
    localparam int BINSTEP = 4;
    int unsigned hist [0:NM-1][0:NBIN-1];

    int unsigned tot_lat, srv_lat;
    int          free_id, bin;

    always @(negedge ACLK) begin
        if (!ARESETn) begin
            cycle    = 0;
            counting = 1'b0;
            for (int m = 0; m < NM; m++) begin
                ARVALID[m] = 1'b0;
                ARID[m]    = '0;
                ARADDR[m]  = SLAVE0_BASE;
                ARLEN[m]   = '0;
                ARBURST[m] = BURST_INCR;
                ARQOS[m]   = '0;
                beats[m]   = 0;
                txns[m]    = 0;
                sumtot[m]  = 0;
                sumsrv[m]  = 0;
                maxtot[m]  = 0;
                credit[m]  = 0;
                for (int i = 0; i < NID; i++) begin
                    id_busy[m][i]   = 1'b0;
                    offer_cyc[m][i] = 0;
                    issue_cyc[m][i] = 0;
                end
                for (int b = 0; b < NBIN; b++) hist[m][b] = 0;
            end
        end else begin
            cycle    = cycle + 1;
            counting = (cycle > WARMUP) && (cycle <= WARMUP + MEASURE);

            //--- 1. retire R beats -------------------------------------
            for (int m = 0; m < NM; m++) begin
                if (RVALID[m] && RREADY[m]) begin
                    if (counting) beats[m] = beats[m] + 1;
                    if (RLAST[m]) begin
                        tot_lat = cycle - offer_cyc[m][RID[m]];
                        srv_lat = cycle - issue_cyc[m][RID[m]];
                        id_busy[m][RID[m]] = 1'b0;
                        if (counting) begin
                            txns[m]   = txns[m] + 1;
                            sumtot[m] = sumtot[m] + tot_lat;
                            sumsrv[m] = sumsrv[m] + srv_lat;
                            if (tot_lat > maxtot[m]) maxtot[m] = tot_lat;
                            bin = tot_lat / BINSTEP;
                            if (bin > NBIN-1) bin = NBIN-1;
                            hist[m][bin] = hist[m][bin] + 1;
                        end
                    end
                end
            end

            //--- 2. complete AR handshakes -----------------------------
            for (int m = 0; m < NM; m++) begin
                if (ARVALID[m] && ARREADY[m]) begin
                    issue_cyc[m][ARID[m]] = cycle;
                    id_busy[m][ARID[m]]   = 1'b1;
                    ARVALID[m]            = 1'b0;
                end
            end

            //--- 3. offer new reads ------------------------------------
            for (int m = 0; m < NM; m++) begin
                credit[m] = credit[m] + load_cfg[m];
                if (credit[m] > 200) credit[m] = 200;
                if (!ARVALID[m] && credit[m] >= 100) begin
                    free_id = -1;
                    for (int i = 0; i < NID; i++)
                        if (!id_busy[m][i] && free_id < 0) free_id = i;
                    if (free_id >= 0) begin
                        credit[m]  = credit[m] - 100;
                        // queue clock starts HERE, not at the handshake
                        offer_cyc[m][free_id[ORIG_ID_WIDTH-1:0]] = cycle;
                        ARID[m]    = free_id[ORIG_ID_WIDTH-1:0];
                        ARADDR[m]  = SLAVE0_BASE;   // all -> slave 0
                        ARLEN[m]   = len_cfg[m][LEN_WIDTH-1:0];
                        ARBURST[m] = BURST_INCR;
                        ARQOS[m]   = qos_cfg[m][QOS_WIDTH-1:0];
                        ARVALID[m] = 1'b1;
                    end
                end
            end
        end
    end

    //---------------- main ------------------------------------------
    real avgtot [0:NM-1];
    real avgsrv [0:NM-1];
    real ratio_12;
    int unsigned p99 [0:NM-1];
    int unsigned acc, thresh;
    int          fd;
    string       csv;

    //---------------- sweep lists -----------------------------------
    int case_list [] = '{ 1, 2 };
    int load_list [] = '{ 1,2,3,5,8,10,15,20,30,40,50,60,70,80,90,91,92,93,94,95,96,97,98,99,100 };

    task automatic run_one(input int c, input int ld);
        // fresh reset so DUT state (deficits, FIFOs, scoreboard) and all
        // measurement counters clear together, then warm up before the
        // measurement window opens.
        CASE_ID = c;
        LOAD    = ld;
        apply_case(c);

        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK);
        ARESETn = 1'b1;

        $display("### run scheme=%0s case=%0d load=%0d%%  warmup=%0d measure=%0d",
                 SCHEME, CASE_ID, LOAD, WARMUP, MEASURE);
        $display("### profile  m0: LEN=%0d QOS=%0d | m1: LEN=%0d QOS=%0d | m2: LEN=%0d QOS=%0d",
                 len_cfg[0], qos_cfg[0], len_cfg[1], qos_cfg[1],
                 len_cfg[2], qos_cfg[2]);

        wait (cycle > WARMUP + MEASURE);
        @(negedge ACLK);

        for (int m = 0; m < NM; m++) begin
            avgtot[m] = (txns[m] > 0) ? real'(sumtot[m]) / real'(txns[m]) : 0.0;
            avgsrv[m] = (txns[m] > 0) ? real'(sumsrv[m]) / real'(txns[m]) : 0.0;
            p99[m] = 0;
            if (txns[m] > 0) begin
                thresh = (txns[m] * 99) / 100;
                acc    = 0;
                for (int b = 0; b < NBIN; b++) begin
                    acc = acc + hist[m][b];
                    if (acc >= thresh && p99[m] == 0)
                        p99[m] = (b + 1) * BINSTEP;
                end
            end
        end
        ratio_12 = (beats[2] > 0) ? real'(beats[1]) / real'(beats[2]) : 0.0;

        $display(" master   beats    txns   avg_tot   avg_srv    p99   max_tot");
        for (int m = 0; m < NM; m++)
            $display("   m%0d   %7d %7d   %7.2f   %7.2f %6d   %7d",
                     m, beats[m], txns[m], avgtot[m], avgsrv[m], p99[m], maxtot[m]);
        $display(" m1:m2 beat ratio = %0.3f", ratio_12);

        $display("RESULT scheme=%0s case=%0d load=%0d beats=%0d,%0d,%0d txns=%0d,%0d,%0d avgtot=%0.2f,%0.2f,%0.2f avgsrv=%0.2f,%0.2f,%0.2f p99=%0d,%0d,%0d maxtot=%0d,%0d,%0d ratio12=%0.4f",
                 SCHEME, CASE_ID, LOAD,
                 beats[0], beats[1], beats[2],
                 txns[0],  txns[1],  txns[2],
                 avgtot[0], avgtot[1], avgtot[2],
                 avgsrv[0], avgsrv[1], avgsrv[2],
                 p99[0], p99[1], p99[2],
                 maxtot[0], maxtot[1], maxtot[2],
                 ratio_12);

        if (fd) begin
            $fwrite(fd, "%0s,%0d,%0d", SCHEME, CASE_ID, LOAD);
            for (int m = 0; m < NM; m++)
                $fwrite(fd, ",%0d,%0d,%0.2f,%0.2f,%0d,%0d",
                        beats[m], txns[m], avgtot[m], avgsrv[m], p99[m], maxtot[m]);
            $fwrite(fd, ",%0.4f\n", ratio_12);
        end
    endtask

    initial begin
        if (!$value$plusargs("SCHEME=%s", SCHEME))  SCHEME  = "RR";
        if (!$value$plusargs("WARMUP=%d",  WARMUP))  WARMUP  = 500;
        if (!$value$plusargs("MEASURE=%d", MEASURE)) MEASURE = 10000;

        // Write path unused: tie it off inactive for the whole run.
        for (int m = 0; m < NM; m++) begin
            AWID[m]='0; AWADDR[m]='0; AWLEN[m]='0; AWBURST[m]=BURST_INCR;
            AWQOS[m]='0; AWVALID[m]=1'b0;
            WDATA[m]='0; WSTRB[m]='1; WLAST[m]=1'b0; WVALID[m]=1'b0;
            BREADY[m]=1'b0;
            RREADY[m]=1'b1;
        end

        if (!$value$plusargs("CSV=%s", csv)) csv = "traffic_results.csv";
        fd = $fopen(csv, "a");

        $display("### weights  MASTER_WEIGHT = {%0d,%0d,%0d}  (config only, not on the bus)",
                 MASTER_WEIGHT[0], MASTER_WEIGHT[1], MASTER_WEIGHT[2]);
        $display("### SWEEP begins: %0d cases x %0d loads",
                 case_list.size(), load_list.size());

        foreach (case_list[ci])
            foreach (load_list[li])
                if (load_list[li] > 0)
                    run_one(case_list[ci], load_list[li]);

        if (fd) $fclose(fd);
        $display("### SWEEP done");
        $finish;
    end

    initial begin
        #200000000;
        $display("*** TIMEOUT at cycle %0d - fabric stalled? ***", cycle);
        $finish;
    end

endmodule
