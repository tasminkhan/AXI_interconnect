//=====================================================================
// top.sv  (AXI4 write path: AW, W, B)
//---------------------------------------------------------------------
//  testbench ==AW/W==> [master: skid buffers] ==*_SKD==> decoder/demux ==> slaves
//  testbench <==B===== [master: B skid]      <==*_MUX== response mux  <== slaves
//
// All widths come from axi_pkg, imported BEFORE the port list so the
// ports themselves are parameterized.
//=====================================================================

import param_pkg::*;

module top (
    input  logic                      ACLK,
    input  logic                      ARESETn,

    //---------------- AW channel -------------------------------------
    input  logic [ID_WIDTH-1:0]       AWID,
    input  logic [ADDRESS_WIDTH-1:0]  AWADDR,
    input  logic [LEN_WIDTH-1:0]      AWLEN,
    input  logic [BURST_WIDTH-1:0]    AWBURST,
    input  logic                      AWVALID,
    output logic                      AWREADY,

    //---------------- W channel --------------------------------------
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [STROBE_WIDTH-1:0]   WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    //---------------- B channel --------------------------------------
    output logic [ID_WIDTH-1:0]       BID,
    output logic [RESP_WIDTH-1:0]     BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    //---------------- AR channel -------------------------------------
    input  logic [ID_WIDTH-1:0]       ARID,
    input  logic [ADDRESS_WIDTH-1:0]  ARADDR,
    input  logic [LEN_WIDTH-1:0]      ARLEN,
    input  logic [BURST_WIDTH-1:0]    ARBURST,
    input  logic [QOS_WIDTH-1:0]      ARQOS,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    //---------------- R channel --------------------------------------
    output logic [ID_WIDTH-1:0]       RID,
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [RESP_WIDTH-1:0]     RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY
);

    //=================================================================
    // Fabric-side nets
    //=================================================================
    logic [ID_WIDTH-1:0]      AWID_SKD;
    logic [ADDRESS_WIDTH-1:0] AWADDR_SKD;
    logic [LEN_WIDTH-1:0]     AWLEN_SKD;
    logic [BURST_WIDTH-1:0]   AWBURST_SKD;

    logic [DATA_WIDTH-1:0]    WDATA_SKD;
    logic [STROBE_WIDTH-1:0]  WSTRB_SKD;
    logic                     WLAST_SKD;

    logic AWVALID_S0, AWVALID_S1, AWVALID_ERR;
    logic AWREADY_S0, AWREADY_S1, AWREADY_ERR;
    logic AWVALID_DMUX, AWREADY_MUX;

    logic WVALID_S0,  WVALID_S1,  WVALID_ERR;
    logic WREADY_S0,  WREADY_S1,  WREADY_ERR;
    logic WVALID_DMUX, WREADY_MUX;

    logic [ID_WIDTH-1:0]   BID_S0,   BID_S1,   BID_ERR;
    logic [RESP_WIDTH-1:0] BRESP_S0, BRESP_S1, BRESP_ERR;
    logic                  BVALID_S0, BVALID_S1, BVALID_ERR;
    logic                  BREADY_S0, BREADY_S1, BREADY_ERR;

    logic [ID_WIDTH-1:0]   BID_MUX;
    logic [RESP_WIDTH-1:0] BRESP_MUX;
    logic                  BVALID_MUX, BREADY_DMUX;
    
    logic [ID_WIDTH-1:0]      ARID_SKD;
    logic [ADDRESS_WIDTH-1:0] ARADDR_SKD;
    logic [LEN_WIDTH-1:0]     ARLEN_SKD;
    logic [BURST_WIDTH-1:0]   ARBURST_SKD;
    logic ARVALID_S0, ARVALID_S1, ARVALID_ERR;
    logic ARREADY_S0, ARREADY_S1, ARREADY_ERR;
    logic ARVALID_DMUX, ARREADY_MUX;

    logic [ID_WIDTH-1:0]   RID_S0, RID_S1, RID_ERR;
    logic [DATA_WIDTH-1:0] RDATA_S0, RDATA_S1, RDATA_ERR;
    logic [RESP_WIDTH-1:0] RRESP_S0, RRESP_S1, RRESP_ERR;
    logic RLAST_S0, RLAST_S1, RLAST_ERR;
    logic RVALID_S0, RVALID_S1, RVALID_ERR;
    logic RREADY_S0, RREADY_S1, RREADY_ERR;

    logic [ID_WIDTH-1:0]   RID_MUX;
    logic [DATA_WIDTH-1:0] RDATA_MUX;
    logic [RESP_WIDTH-1:0] RRESP_MUX;
    logic RLAST_MUX, RVALID_MUX, RREADY_DMUX;

    //=================================================================
    // DECODER (combinational) - target select + burst pre-check.
    //=================================================================
    logic [SELECT_WIDTH-1:0] aw_sel;

    aw_decoder u_awdecoder (
        .AWADDR_SKD  (AWADDR_SKD),
        .AWLEN_SKD   (AWLEN_SKD),
        .AWBURST_SKD (AWBURST_SKD),
        .aw_sel      (aw_sel)
    );

    //=================================================================
    // SELECT FIFO - one memory, one write pointer, one read pointer.
    //=================================================================
    // Each entry stores the target AND the burst length, so the fabric
    // can count beats itself. Termination is COUNTER-authoritative
    // (w_beat == len) with WLAST as an early terminator 
    logic [SELECT_WIDTH-1:0]     sel_mem [0:SELECT_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]        len_mem [0:SELECT_FIFO_DEPTH-1];
    logic [SELECT_PTR_WIDTH-1:0] sel_aw_wp, sel_w_rp;
    logic [BEAT_COUNT_WIDTH-1:0] w_beat;              // beats seen in current burst

    wire sel_empty = (sel_aw_wp == sel_w_rp);
    wire sel_full  = (sel_aw_wp[SELECT_PTR_WIDTH-2:0] == sel_w_rp[SELECT_PTR_WIDTH-2:0])
                   & (sel_aw_wp[SELECT_PTR_WIDTH-1]   != sel_w_rp[SELECT_PTR_WIDTH-1]);

    wire [SELECT_WIDTH-1:0] wsel_head = sel_mem[sel_w_rp[SELECT_PTR_WIDTH-2:0]];
    wire [LEN_WIDTH-1:0]    wlen_head = len_mem[sel_w_rp[SELECT_PTR_WIDTH-2:0]];

    wire w_hs       = WVALID_DMUX & WREADY_MUX;       // a beat transferred
    wire w_burst_end = w_hs & ((w_beat == wlen_head) | WLAST_SKD);

    //=================================================================
    // AW DEMUX (live decode) : payload broadcast, VALID steered.
    // AW acceptance is stalled while the select FIFO is full.
    //=================================================================
    always_comb begin
        AWVALID_S0  = AWVALID_DMUX & ~sel_full & (aw_sel == SEL_S0);
        AWVALID_S1  = AWVALID_DMUX & ~sel_full & (aw_sel == SEL_S1);
        AWVALID_ERR = AWVALID_DMUX & ~sel_full & (aw_sel == SEL_ERR);

        case (aw_sel)
            SEL_S0:  AWREADY_MUX = AWREADY_S0  & ~sel_full;
            SEL_S1:  AWREADY_MUX = AWREADY_S1  & ~sel_full;
            default: AWREADY_MUX = AWREADY_ERR & ~sel_full;
        endcase
    end

    //=================================================================
    // W DEMUX (latched select = wsel_head) : payload broadcast,
    // VALID steered by the OLDEST burst still awaiting data. W is held
    // off until an AW has been accepted - beats have no routing before
    // their address, so a stale wsel_head can never steer a beat.
    //=================================================================
    always_comb begin
        WVALID_S0  = WVALID_DMUX & ~sel_empty & (wsel_head == SEL_S0);
        WVALID_S1  = WVALID_DMUX & ~sel_empty & (wsel_head == SEL_S1);
        WVALID_ERR = WVALID_DMUX & ~sel_empty & (wsel_head == SEL_ERR);

        case (wsel_head)
            SEL_S0:  WREADY_MUX = WREADY_S0  & ~sel_empty;
            SEL_S1:  WREADY_MUX = WREADY_S1  & ~sel_empty;
            default: WREADY_MUX = WREADY_ERR & ~sel_empty;
        endcase
    end
    
    //=================================================================
    // Sequential : select FIFO pointers 
    //=================================================================
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            sel_aw_wp <= '0;
            sel_w_rp  <= '0;
            w_beat    <= '0;
        end else begin
            if (AWVALID_DMUX && AWREADY_MUX) begin           // address accepted
                sel_mem[sel_aw_wp[SELECT_PTR_WIDTH-2:0]] <= aw_sel;
                len_mem[sel_aw_wp[SELECT_PTR_WIDTH-2:0]] <= AWLEN_SKD;
                sel_aw_wp <= sel_aw_wp + 1'b1;
            end
            if (w_burst_end) begin                // burst data done -> retire entry
                sel_w_rp <= sel_w_rp + 1'b1;
                w_beat   <= '0;
            end else if (w_hs)                    // mid-burst beat
                w_beat <= w_beat + 1'b1;
        end
    end
    
    //=================================================================
    // B ARBITER + MUX, Muxing in round robin fashion
    //=================================================================
    b_arbiter u_b_arbiter (
        .ACLK(ACLK), .ARESETn(ARESETn),

        .BID_S0(BID_S0),     .BID_S1(BID_S1),     .BID_ERR(BID_ERR),
        .BRESP_S0(BRESP_S0), .BRESP_S1(BRESP_S1), .BRESP_ERR(BRESP_ERR),
        .BVALID_S0(BVALID_S0), .BVALID_S1(BVALID_S1), .BVALID_ERR(BVALID_ERR),

        .BREADY_S0(BREADY_S0), .BREADY_S1(BREADY_S1), .BREADY_ERR(BREADY_ERR),

        .BID_MUX(BID_MUX), .BRESP_MUX(BRESP_MUX),
        .BVALID_MUX(BVALID_MUX), .BREADY_DMUX(BREADY_DMUX)
    );
    
    //=================================================================
    // AR DECODER (combinational) - target select + burst pre-check.
    //=================================================================
    logic [SELECT_WIDTH-1:0] ar_sel;

    ar_decoder u_ardecoder (
        .ARADDR_SKD  (ARADDR_SKD),
        .ARLEN_SKD   (ARLEN_SKD),
        .ARBURST_SKD (ARBURST_SKD),
        .ar_sel      (ar_sel)
    );

    //=================================================================
    // AR DEMUX (live decode) : payload broadcast, VALID steered.
    // R routes itself by RID through the arbiter; 
    // each slave's AR FIFO backpressures via ARREADY.
    //=================================================================
    always_comb begin
        ARVALID_S0  = ARVALID_DMUX & (ar_sel == SEL_S0);
        ARVALID_S1  = ARVALID_DMUX & (ar_sel == SEL_S1);
        ARVALID_ERR = ARVALID_DMUX & (ar_sel == SEL_ERR);

        case (ar_sel)
            SEL_S0:  ARREADY_MUX = ARREADY_S0;
            SEL_S1:  ARREADY_MUX = ARREADY_S1;
            default: ARREADY_MUX = ARREADY_ERR;
        endcase
    end

    //=================================================================
    // R ARBITER + MUX (round-robin, burst-locked to RLAST)
    //=================================================================
    r_arbiter u_r_arbiter (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .RID_S0(RID_S0),     .RID_S1(RID_S1),     .RID_ERR(RID_ERR),
        .RDATA_S0(RDATA_S0), .RDATA_S1(RDATA_S1), .RDATA_ERR(RDATA_ERR),
        .RRESP_S0(RRESP_S0), .RRESP_S1(RRESP_S1), .RRESP_ERR(RRESP_ERR),
        .RLAST_S0(RLAST_S0), .RLAST_S1(RLAST_S1), .RLAST_ERR(RLAST_ERR),
        .RVALID_S0(RVALID_S0), .RVALID_S1(RVALID_S1), .RVALID_ERR(RVALID_ERR),
        .RREADY_S0(RREADY_S0), .RREADY_S1(RREADY_S1), .RREADY_ERR(RREADY_ERR),
        .RID_MUX(RID_MUX), .RDATA_MUX(RDATA_MUX), .RRESP_MUX(RRESP_MUX),
        .RLAST_MUX(RLAST_MUX), .RVALID_MUX(RVALID_MUX), .RREADY_DMUX(RREADY_DMUX)
    );
    
    //=================================================================
    // Master : the three always-on skid buffers
    //=================================================================
    master u_master (
        .ACLK(ACLK), .ARESETn(ARESETn),

        .AWID(AWID), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWBURST(AWBURST),
        .AWVALID(AWVALID), .AWREADY(AWREADY),

        .AWID_SKD(AWID_SKD), .AWADDR_SKD(AWADDR_SKD),
        .AWLEN_SKD(AWLEN_SKD), .AWBURST_SKD(AWBURST_SKD),
        .AWVALID_DMUX(AWVALID_DMUX), .AWREADY_MUX(AWREADY_MUX),

        .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST),
        .WVALID(WVALID), .WREADY(WREADY),

        .WDATA_SKD(WDATA_SKD), .WSTRB_SKD(WSTRB_SKD), .WLAST_SKD(WLAST_SKD),
        .WVALID_DMUX(WVALID_DMUX), .WREADY_MUX(WREADY_MUX),

        .BID_MUX(BID_MUX), .BRESP_MUX(BRESP_MUX),
        .BVALID_MUX(BVALID_MUX), .BREADY_DMUX(BREADY_DMUX),

        .BID(BID), .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        
        .ARID(ARID), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARBURST(ARBURST),
        .ARQOS(ARQOS),
        .ARVALID(ARVALID), .ARREADY(ARREADY),
        .ARID_SKD(ARID_SKD), .ARADDR_SKD(ARADDR_SKD),
        .ARLEN_SKD(ARLEN_SKD), .ARBURST_SKD(ARBURST_SKD),
        .ARQOS_SKD(ARQOS_SKD),
        .ARVALID_DMUX(ARVALID_DMUX), .ARREADY_MUX(ARREADY_MUX),

        .RID_MUX(RID_MUX), .RDATA_MUX(RDATA_MUX), .RRESP_MUX(RRESP_MUX),
        .RLAST_MUX(RLAST_MUX), .RVALID_MUX(RVALID_MUX), .RREADY_DMUX(RREADY_DMUX),
        .RID(RID), .RDATA(RDATA), .RRESP(RRESP),
        .RLAST(RLAST), .RVALID(RVALID), .RREADY(RREADY)
    );

    //=================================================================
    // Slaves : payload broadcast, per-target VALID/READY wired
    //=================================================================
    slave #(.BASE_ADDR(SLAVE0_BASE)) u_slave0 (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_SKD), .AWADDR_I(AWADDR_SKD), .AWLEN_I(AWLEN_SKD),
        .AWVALID_I(AWVALID_S0), .AWREADY_O(AWREADY_S0),
        .WDATA_I(WDATA_SKD), .WSTRB_I(WSTRB_SKD), .WLAST_I(WLAST_SKD),
        .WVALID_I(WVALID_S0), .WREADY_O(WREADY_S0),
        .BID_O(BID_S0), .BRESP_O(BRESP_S0),
        .BVALID_O(BVALID_S0), .BREADY_I(BREADY_S0),
        .ARID_I(ARID_SKD), .ARADDR_I(ARADDR_SKD), .ARLEN_I(ARLEN_SKD),
        .ARVALID_I(ARVALID_S0), .ARREADY_O(ARREADY_S0),
        .RID_O(RID_S0), .RDATA_O(RDATA_S0), .RRESP_O(RRESP_S0),
        .RLAST_O(RLAST_S0), .RVALID_O(RVALID_S0), .RREADY_I(RREADY_S0)
    );

    slave #(.BASE_ADDR(SLAVE1_BASE)) u_slave1 (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_SKD), .AWADDR_I(AWADDR_SKD), .AWLEN_I(AWLEN_SKD),
        .AWVALID_I(AWVALID_S1), .AWREADY_O(AWREADY_S1),
        .WDATA_I(WDATA_SKD), .WSTRB_I(WSTRB_SKD), .WLAST_I(WLAST_SKD),
        .WVALID_I(WVALID_S1), .WREADY_O(WREADY_S1),
        .BID_O(BID_S1), .BRESP_O(BRESP_S1),
        .BVALID_O(BVALID_S1), .BREADY_I(BREADY_S1),
        .ARID_I(ARID_SKD), .ARADDR_I(ARADDR_SKD), .ARLEN_I(ARLEN_SKD),
        .ARVALID_I(ARVALID_S1), .ARREADY_O(ARREADY_S1),
        .RID_O(RID_S1), .RDATA_O(RDATA_S1), .RRESP_O(RRESP_S1),
        .RLAST_O(RLAST_S1), .RVALID_O(RVALID_S1), .RREADY_I(RREADY_S1)
    );

    //=================================================================
    // Pseudo-slave : terminates DECERR bursts (drains beats, no write)
    //=================================================================
    err_slave u_err_slave (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_SKD), .AWLEN_I(AWLEN_SKD),
        .AWVALID_I(AWVALID_ERR), .AWREADY_O(AWREADY_ERR),
        .WLAST_I(WLAST_SKD),
        .WVALID_I(WVALID_ERR), .WREADY_O(WREADY_ERR),
        .BID_O(BID_ERR), .BRESP_O(BRESP_ERR),
        .BVALID_O(BVALID_ERR), .BREADY_I(BREADY_ERR),
        .ARID_I(ARID_SKD), .ARLEN_I(ARLEN_SKD),
        .ARVALID_I(ARVALID_ERR), .ARREADY_O(ARREADY_ERR),
        .RID_O(RID_ERR), .RDATA_O(RDATA_ERR), .RRESP_O(RRESP_ERR),
        .RLAST_O(RLAST_ERR), .RVALID_O(RVALID_ERR), .RREADY_I(RREADY_ERR)
    );

endmodule