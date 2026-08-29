import param_pkg::*;

module top_reorder1 (
    input  logic                      ACLK,
    input  logic                      ARESETn,

    //================ AW CHANNEL =====================================
    input  logic [ID_WIDTH-1:0]       AWID,
    input  logic [ADDRESS_WIDTH-1:0]  AWADDR,
    input  logic [LEN_WIDTH-1:0]      AWLEN,
    input  logic [BURST_WIDTH-1:0]    AWBURST,
    input  logic                      AWVALID,
    output logic                      AWREADY,

    //================ W CHANNEL ======================================
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [STROBE_WIDTH-1:0]   WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    //================ B CHANNEL ======================================
    output logic [ID_WIDTH-1:0]       BID,
    output logic [RESP_WIDTH-1:0]     BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    //================ AR CHANNEL =====================================
    input  logic [ID_WIDTH-1:0]       ARID,
    input  logic [ADDRESS_WIDTH-1:0]  ARADDR,
    input  logic [LEN_WIDTH-1:0]      ARLEN,
    input  logic [BURST_WIDTH-1:0]    ARBURST,
    input  logic [QOS_WIDTH-1:0]      ARQOS,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    //================ R CHANNEL ======================================
    output logic [ID_WIDTH-1:0]       RID,
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [RESP_WIDTH-1:0]     RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY
);
    //================ FABRIC-SIDE NETS ===============================
    logic [ID_WIDTH-1:0]      AWID_SKD;
    logic [ADDRESS_WIDTH-1:0] AWADDR_SKD;
    logic [LEN_WIDTH-1:0]     AWLEN_SKD;
    logic [BURST_WIDTH-1:0]   AWBURST_SKD;

    logic [DATA_WIDTH-1:0]    WDATA_SKD;
    logic [STROBE_WIDTH-1:0]  WSTRB_SKD;
    logic                     WLAST_SKD;

    logic AWVALID_S1, AWVALID_ERR;
    logic AWREADY_S1, AWREADY_ERR;
    logic AWVALID_DMUX, AWREADY_MUX;

    logic WVALID_S1, WVALID_ERR;
    logic WREADY_S1, WREADY_ERR;
    logic WVALID_DMUX, WREADY_MUX;

    logic [ID_WIDTH-1:0]   BID_S1,   BID_ERR;
    logic [RESP_WIDTH-1:0] BRESP_S1, BRESP_ERR;
    logic                  BVALID_S1, BVALID_ERR;
    logic                  BREADY_S1, BREADY_ERR;

    logic [ID_WIDTH-1:0]   BID_MUX;
    logic [RESP_WIDTH-1:0] BRESP_MUX;
    logic                  BVALID_MUX, BREADY_DMUX;

    logic [ID_WIDTH-1:0]      ARID_SKD;
    logic [ADDRESS_WIDTH-1:0] ARADDR_SKD;
    logic [LEN_WIDTH-1:0]     ARLEN_SKD;
    logic [BURST_WIDTH-1:0]   ARBURST_SKD;
    logic [QOS_WIDTH-1:0]     ARQOS_SKD;
    logic ARVALID_S1, ARVALID_ERR;
    logic ARREADY_S1, ARREADY_ERR;
    logic ARVALID_DMUX, ARREADY_MUX;

    logic [ID_WIDTH-1:0]   RID_S1, RID_ERR;
    logic [DATA_WIDTH-1:0] RDATA_S1, RDATA_ERR;
    logic [RESP_WIDTH-1:0] RRESP_S1, RRESP_ERR;
    logic RLAST_S1, RLAST_ERR;
    logic RVALID_S1, RVALID_ERR;
    logic RREADY_S1, RREADY_ERR;

    logic [ID_WIDTH-1:0]   RID_MUX;
    logic [DATA_WIDTH-1:0] RDATA_MUX;
    logic [RESP_WIDTH-1:0] RRESP_MUX;
    logic RLAST_MUX, RVALID_MUX, RREADY_DMUX;

    //================ ID SCOREBOARD ==================================
    localparam int NUM_IDS = 1 << ID_WIDTH;
    logic [NUM_IDS-1:0] aw_id_busy;
    logic [NUM_IDS-1:0] ar_id_busy;

    wire aw_issue    = AWVALID_DMUX & AWREADY_MUX;
    wire b_retire    = BVALID_MUX   & BREADY_DMUX;
    wire aw_id_stall = aw_id_busy[AWID_SKD];

    wire ar_issue    = ARVALID_DMUX & ARREADY_MUX;
    wire r_retire    = RVALID_MUX   & RREADY_DMUX & RLAST_MUX;
    wire ar_id_stall = ar_id_busy[ARID_SKD];

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            aw_id_busy <= '0;
            ar_id_busy <= '0;
        end else begin
            if (b_retire) aw_id_busy[BID_MUX]  <= 1'b0;
            if (aw_issue) aw_id_busy[AWID_SKD] <= 1'b1;
            if (r_retire) ar_id_busy[RID_MUX]  <= 1'b0;
            if (ar_issue) ar_id_busy[ARID_SKD] <= 1'b1;
        end
    end

    //================ AW DECODER =====================================
    logic [SELECT_WIDTH-1:0] aw_sel;
    aw_decoder_1 u_awdecoder (
        .AWADDR_SKD(AWADDR_SKD), .AWLEN_SKD(AWLEN_SKD),
        .AWBURST_SKD(AWBURST_SKD), .aw_sel(aw_sel)
    );

    //================ SELECT FIFO ====================================
    logic [SELECT_WIDTH-1:0]     sel_mem [0:SELECT_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]        len_mem [0:SELECT_FIFO_DEPTH-1];
    logic [SELECT_PTR_WIDTH-1:0] sel_aw_wp, sel_w_rp;
    logic [BEAT_COUNT_WIDTH-1:0] w_beat;

    wire sel_empty = (sel_aw_wp == sel_w_rp);
    wire sel_full  = (sel_aw_wp[SELECT_PTR_WIDTH-2:0] == sel_w_rp[SELECT_PTR_WIDTH-2:0])
                   & (sel_aw_wp[SELECT_PTR_WIDTH-1]   != sel_w_rp[SELECT_PTR_WIDTH-1]);

    wire [SELECT_WIDTH-1:0] wsel_head = sel_mem[sel_w_rp[SELECT_PTR_WIDTH-2:0]];
    wire [LEN_WIDTH-1:0]    wlen_head = len_mem[sel_w_rp[SELECT_PTR_WIDTH-2:0]];

    wire w_hs        = WVALID_DMUX & WREADY_MUX;
    wire w_burst_end = w_hs & ((w_beat == wlen_head) | WLAST_SKD);

    //================ AW DEMUX =======================================
    always_comb begin
        AWVALID_S1  = AWVALID_DMUX & ~sel_full & ~aw_id_stall & (aw_sel == SEL_S1);
        AWVALID_ERR = AWVALID_DMUX & ~sel_full & ~aw_id_stall & (aw_sel == SEL_ERR);
        case (aw_sel)
            SEL_S1:  AWREADY_MUX = AWREADY_S1  & ~sel_full & ~aw_id_stall;
            default: AWREADY_MUX = AWREADY_ERR & ~sel_full & ~aw_id_stall;
        endcase
    end

    //================ W DEMUX ========================================
    always_comb begin
        WVALID_S1  = WVALID_DMUX & ~sel_empty & (wsel_head == SEL_S1);
        WVALID_ERR = WVALID_DMUX & ~sel_empty & (wsel_head == SEL_ERR);
        case (wsel_head)
            SEL_S1:  WREADY_MUX = WREADY_S1  & ~sel_empty;
            default: WREADY_MUX = WREADY_ERR & ~sel_empty;
        endcase
    end

    //================ SELECT FIFO POINTERS ===========================
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            sel_aw_wp <= '0; sel_w_rp <= '0; w_beat <= '0;
        end else begin
            if (AWVALID_DMUX && AWREADY_MUX) begin
                sel_mem[sel_aw_wp[SELECT_PTR_WIDTH-2:0]] <= aw_sel;
                len_mem[sel_aw_wp[SELECT_PTR_WIDTH-2:0]] <= AWLEN_SKD;
                sel_aw_wp <= sel_aw_wp + 1'b1;
            end
            if (w_burst_end) begin
                sel_w_rp <= sel_w_rp + 1'b1;
                w_beat   <= '0;
            end else if (w_hs)
                w_beat <= w_beat + 1'b1;
        end
    end

    //================ B ARBITER + MUX ================================
    b_arbiter1 u_b_arbiter (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .BID_S1(BID_S1), .BID_ERR(BID_ERR),
        .BRESP_S1(BRESP_S1), .BRESP_ERR(BRESP_ERR),
        .BVALID_S1(BVALID_S1), .BVALID_ERR(BVALID_ERR),
        .BREADY_S1(BREADY_S1), .BREADY_ERR(BREADY_ERR),
        .BID_MUX(BID_MUX), .BRESP_MUX(BRESP_MUX),
        .BVALID_MUX(BVALID_MUX), .BREADY_DMUX(BREADY_DMUX)
    );

    //================ AR DECODER =====================================
    logic [SELECT_WIDTH-1:0] ar_sel;
    ar_decoder_1 u_ardecoder (
        .ARADDR_SKD(ARADDR_SKD), .ARLEN_SKD(ARLEN_SKD),
        .ARBURST_SKD(ARBURST_SKD), .ar_sel(ar_sel)
    );

    //================ AR DEMUX =======================================
    always_comb begin
        ARVALID_S1  = ARVALID_DMUX & ~ar_id_stall & (ar_sel == SEL_S1);
        ARVALID_ERR = ARVALID_DMUX & ~ar_id_stall & (ar_sel == SEL_ERR);
        case (ar_sel)
            SEL_S1:  ARREADY_MUX = ARREADY_S1  & ~ar_id_stall;
            default: ARREADY_MUX = ARREADY_ERR & ~ar_id_stall;
        endcase
    end

    //================ R ARBITER + MUX ================================
    r_arbiter1 u_r_arbiter (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .RID_S1(RID_S1), .RID_ERR(RID_ERR),
        .RDATA_S1(RDATA_S1), .RDATA_ERR(RDATA_ERR),
        .RRESP_S1(RRESP_S1), .RRESP_ERR(RRESP_ERR),
        .RLAST_S1(RLAST_S1), .RLAST_ERR(RLAST_ERR),
        .RVALID_S1(RVALID_S1), .RVALID_ERR(RVALID_ERR),
        .RREADY_S1(RREADY_S1), .RREADY_ERR(RREADY_ERR),
        .RID_MUX(RID_MUX), .RDATA_MUX(RDATA_MUX), .RRESP_MUX(RRESP_MUX),
        .RLAST_MUX(RLAST_MUX), .RVALID_MUX(RVALID_MUX), .RREADY_DMUX(RREADY_DMUX)
    );

    //================ MASTER =========================================
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

    //================ SLAVE 1 ========================================
slave_reorder #(.BASE_ADDR(SLAVE1_BASE)) u_slave1 (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(AWID_SKD), .AWADDR_I(AWADDR_SKD), .AWLEN_I(AWLEN_SKD),
        .AWVALID_I(AWVALID_S1), .AWREADY_O(AWREADY_S1),
        .WDATA_I(WDATA_SKD), .WSTRB_I(WSTRB_SKD), .WLAST_I(WLAST_SKD),
        .WVALID_I(WVALID_S1), .WREADY_O(WREADY_S1),
        .BID_O(BID_S1), .BRESP_O(BRESP_S1),
        .BVALID_O(BVALID_S1), .BREADY_I(BREADY_S1),
        .ARID_I(ARID_SKD), .ARADDR_I(ARADDR_SKD), .ARLEN_I(ARLEN_SKD),
        .ARQOS_I(ARQOS_SKD),
        .ARVALID_I(ARVALID_S1), .ARREADY_O(ARREADY_S1),
        .RID_O(RID_S1), .RDATA_O(RDATA_S1), .RRESP_O(RRESP_S1),
        .RLAST_O(RLAST_S1), .RVALID_O(RVALID_S1), .RREADY_I(RREADY_S1)
    );
    //================ ERR SLAVE ======================================
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
