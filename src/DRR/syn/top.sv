`timescale 1ns / 1ps
import param_pkg::*;

module top (
    input  logic ACLK,
    input  logic ARESETn,

    input  logic [ORIG_ID_WIDTH-1:0]  AWID    [0:NUM_MASTERS-1],
    input  logic [ADDRESS_WIDTH-1:0]  AWADDR  [0:NUM_MASTERS-1],
    input  logic [LEN_WIDTH-1:0]      AWLEN   [0:NUM_MASTERS-1],
    input  logic [BURST_WIDTH-1:0]    AWBURST [0:NUM_MASTERS-1],
    input  logic [QOS_WIDTH-1:0]      AWQOS   [0:NUM_MASTERS-1],
    input  logic                      AWVALID [0:NUM_MASTERS-1],
    output logic                      AWREADY [0:NUM_MASTERS-1],

    input  logic [DATA_WIDTH-1:0]     WDATA   [0:NUM_MASTERS-1],
    input  logic [STROBE_WIDTH-1:0]   WSTRB   [0:NUM_MASTERS-1],
    input  logic                      WLAST   [0:NUM_MASTERS-1],
    input  logic                      WVALID  [0:NUM_MASTERS-1],
    output logic                      WREADY  [0:NUM_MASTERS-1],

    output logic [ORIG_ID_WIDTH-1:0]  BID     [0:NUM_MASTERS-1],
    output logic [RESP_WIDTH-1:0]     BRESP   [0:NUM_MASTERS-1],
    output logic                      BVALID  [0:NUM_MASTERS-1],
    input  logic                      BREADY  [0:NUM_MASTERS-1],

    input  logic [ORIG_ID_WIDTH-1:0]  ARID    [0:NUM_MASTERS-1],
    input  logic [ADDRESS_WIDTH-1:0]  ARADDR  [0:NUM_MASTERS-1],
    input  logic [LEN_WIDTH-1:0]      ARLEN   [0:NUM_MASTERS-1],
    input  logic [BURST_WIDTH-1:0]    ARBURST [0:NUM_MASTERS-1],
    input  logic [QOS_WIDTH-1:0]      ARQOS   [0:NUM_MASTERS-1],
    input  logic                      ARVALID [0:NUM_MASTERS-1],
    output logic                      ARREADY [0:NUM_MASTERS-1],

    output logic [ORIG_ID_WIDTH-1:0]  RID     [0:NUM_MASTERS-1],
    output logic [DATA_WIDTH-1:0]     RDATA   [0:NUM_MASTERS-1],
    output logic [RESP_WIDTH-1:0]     RRESP   [0:NUM_MASTERS-1],
    output logic                      RLAST   [0:NUM_MASTERS-1],
    output logic                      RVALID  [0:NUM_MASTERS-1],
    input  logic                      RREADY  [0:NUM_MASTERS-1],

    //---------------- EXTERNAL REGISTER FILE INTERFACE ---------------
    // One port per slave. The register arrays are external to this block.
    output logic                                 REGS_WE    [0:NUM_SLAVES-1],
    output logic [($clog2(SLAVE_REG_COUNT))-1:0] REGS_WADDR [0:NUM_SLAVES-1],
    output logic [DATA_WIDTH-1:0]                REGS_WDATA [0:NUM_SLAVES-1],
    output logic [STROBE_WIDTH-1:0]              REGS_WSTRB [0:NUM_SLAVES-1],
    output logic [($clog2(SLAVE_REG_COUNT))-1:0] REGS_RADDR [0:NUM_SLAVES-1],
    input  logic [DATA_WIDTH-1:0]                REGS_RDATA [0:NUM_SLAVES-1]
);
    localparam int MW      = MASTER_IDX_WIDTH;
    localparam int NUM_IDS = 1 << ID_WIDTH;

    // parameter sanity checks (see param_assert in param_pkg.sv)
    param_assert u_param_assert ();

    //================ OUTPUT MIRRORS ================================
    logic                     awready_i [0:NUM_MASTERS-1];
    logic                     wready_i  [0:NUM_MASTERS-1];
    logic [ORIG_ID_WIDTH-1:0] bid_i     [0:NUM_MASTERS-1];
    logic [RESP_WIDTH-1:0]    bresp_i   [0:NUM_MASTERS-1];
    logic                     bvalid_i  [0:NUM_MASTERS-1];
    logic                     arready_i [0:NUM_MASTERS-1];
    logic [ORIG_ID_WIDTH-1:0] rid_i     [0:NUM_MASTERS-1];
    logic [DATA_WIDTH-1:0]    rdata_i   [0:NUM_MASTERS-1];
    logic [RESP_WIDTH-1:0]    rresp_i   [0:NUM_MASTERS-1];
    logic                     rlast_i   [0:NUM_MASTERS-1];
    logic                     rvalid_i  [0:NUM_MASTERS-1];

    //================ PER-MASTER FABRIC-SIDE NETS ===================
    logic [ID_WIDTH-1:0]      awid_tag     [0:NUM_MASTERS-1];
    logic [ADDRESS_WIDTH-1:0] awaddr_skd   [0:NUM_MASTERS-1];
    logic [LEN_WIDTH-1:0]     awlen_skd    [0:NUM_MASTERS-1];
    logic [QOS_WIDTH-1:0]     awqos_skd    [0:NUM_MASTERS-1];
    logic [SELECT_WIDTH-1:0]  aw_sel       [0:NUM_MASTERS-1];
    logic                     aw_valid_skd [0:NUM_MASTERS-1];
    logic                     aw_ready_skd [0:NUM_MASTERS-1];

    logic [DATA_WIDTH-1:0]    wdata_skd    [0:NUM_MASTERS-1];
    logic [STROBE_WIDTH-1:0]  wstrb_skd    [0:NUM_MASTERS-1];
    logic                     wlast_skd    [0:NUM_MASTERS-1];
    logic                     w_valid_skd  [0:NUM_MASTERS-1];
    logic                     w_ready_skd  [0:NUM_MASTERS-1];

    logic [ID_WIDTH-1:0]      arid_tag     [0:NUM_MASTERS-1];
    logic [ADDRESS_WIDTH-1:0] araddr_skd   [0:NUM_MASTERS-1];
    logic [LEN_WIDTH-1:0]     arlen_skd    [0:NUM_MASTERS-1];
    logic [QOS_WIDTH-1:0]     arqos_skd    [0:NUM_MASTERS-1];
    logic [SELECT_WIDTH-1:0]  ar_sel       [0:NUM_MASTERS-1];
    logic                     ar_valid_skd [0:NUM_MASTERS-1];
    logic                     ar_ready_skd [0:NUM_MASTERS-1];

    logic [SELECT_WIDTH-1:0]  wdest_head   [0:NUM_MASTERS-1];
    logic                     wdest_empty  [0:NUM_MASTERS-1];
    logic                     wdest_full   [0:NUM_MASTERS-1];
    logic                     wdest_push   [0:NUM_MASTERS-1];
    logic [SELECT_WIDTH-1:0]  wdest_push_slot[0:NUM_MASTERS-1];
    logic                     wdest_pop    [0:NUM_MASTERS-1];

    logic                     b_retire     [0:NUM_MASTERS-1];
    logic [ID_WIDTH-1:0]      b_retire_id  [0:NUM_MASTERS-1];
    logic                     r_retire     [0:NUM_MASTERS-1];
    logic [ID_WIDTH-1:0]      r_retire_id  [0:NUM_MASTERS-1];

    // per slot, one bit per master (packed: robust for cross-generate drives)
    logic [NUM_MASTERS-1:0] b_ready_bits [0:NUM_TARGETS-1];
    logic [NUM_MASTERS-1:0] r_ready_bits [0:NUM_TARGETS-1];

    //================ PER-SLOT NETS =================================
    // Slot 0..NUM_SLAVES-1 = real slaves, slot NUM_SLAVES = err target.
    logic [ID_WIDTH-1:0]      aw_id           [0:NUM_TARGETS-1];
    logic [ADDRESS_WIDTH-1:0] aw_addr         [0:NUM_TARGETS-1];
    logic [LEN_WIDTH-1:0]     aw_len          [0:NUM_TARGETS-1];
    logic [QOS_WIDTH-1:0]     aw_qos          [0:NUM_TARGETS-1];
    logic                     aw_arbout_valid [0:NUM_TARGETS-1];
    logic                     aw_arbout_ready [0:NUM_TARGETS-1];
    logic [NUM_MASTERS-1:0]   aw_arbin_valid  [0:NUM_TARGETS-1];
    logic [NUM_MASTERS-1:0]   aw_arbin_ready  [0:NUM_TARGETS-1];
    logic                     aw_grant_valid  [0:NUM_TARGETS-1];
    logic [MW-1:0]            aw_grant_idx    [0:NUM_TARGETS-1];

    logic [DATA_WIDTH-1:0]    w_data          [0:NUM_TARGETS-1];
    logic [STROBE_WIDTH-1:0]  w_strb          [0:NUM_TARGETS-1];
    logic                     w_last          [0:NUM_TARGETS-1];
    logic                     w_arbout_valid  [0:NUM_TARGETS-1];
    logic                     w_arbout_ready  [0:NUM_TARGETS-1];
    logic [MASTER_TAG_WIDTH-1:0] w_owner      [0:NUM_TARGETS-1];
    logic                     w_owner_valid   [0:NUM_TARGETS-1];
    logic                     w_burst_end     [0:NUM_TARGETS-1];

    logic [ID_WIDTH-1:0]      ar_id           [0:NUM_TARGETS-1];
    logic [ADDRESS_WIDTH-1:0] ar_addr         [0:NUM_TARGETS-1];
    logic [LEN_WIDTH-1:0]     ar_len          [0:NUM_TARGETS-1];
    logic [QOS_WIDTH-1:0]     ar_qos          [0:NUM_TARGETS-1];
    logic                     ar_arbout_valid [0:NUM_TARGETS-1];
    logic                     ar_arbout_ready [0:NUM_TARGETS-1];
    logic [NUM_MASTERS-1:0]   ar_arbin_valid  [0:NUM_TARGETS-1];
    logic [NUM_MASTERS-1:0]   ar_arbin_ready  [0:NUM_TARGETS-1];
    logic                     ar_grant_valid  [0:NUM_TARGETS-1];
    logic [MW-1:0]            ar_grant_idx    [0:NUM_TARGETS-1];

    logic [ID_WIDTH-1:0]      b_id_s   [0:NUM_TARGETS-1];
    logic [RESP_WIDTH-1:0]    b_resp_s [0:NUM_TARGETS-1];
    logic [QOS_WIDTH-1:0]     b_qos_s  [0:NUM_TARGETS-1];   // sideband, not AXI
    logic                     b_valid_s[0:NUM_TARGETS-1];
    logic                     b_ready_s[0:NUM_TARGETS-1];

    logic [ID_WIDTH-1:0]      r_id_s   [0:NUM_TARGETS-1];
    logic [DATA_WIDTH-1:0]    r_data_s [0:NUM_TARGETS-1];
    logic [RESP_WIDTH-1:0]    r_resp_s [0:NUM_TARGETS-1];
    logic [QOS_WIDTH-1:0]     r_qos_s  [0:NUM_TARGETS-1];   // sideband, not AXI
    logic                     r_last_s [0:NUM_TARGETS-1];
    logic                     r_valid_s[0:NUM_TARGETS-1];
    logic                     r_ready_s[0:NUM_TARGETS-1];

    //================ ID SCOREBOARD =================================
    logic [NUM_IDS-1:0] aw_id_busy, ar_id_busy;
    logic aw_id_stall [0:NUM_MASTERS-1];
    logic ar_id_stall [0:NUM_MASTERS-1];

    genvar gm, gt, gu;
    generate
        for (gm = 0; gm < NUM_MASTERS; gm++) begin : g_stall
            assign aw_id_stall[gm] = aw_id_busy[awid_tag[gm]];
            assign ar_id_stall[gm] = ar_id_busy[arid_tag[gm]];
        end
    endgenerate

    //================ REQUEST MATRICES ==============================
    generate
        for (gt = 0; gt < NUM_TARGETS; gt++) begin : g_req
            for (gm = 0; gm < NUM_MASTERS; gm++) begin : g_reqm
                assign aw_arbin_valid[gt][gm] =
                    aw_valid_skd[gm] & (aw_sel[gm] == gt[SELECT_WIDTH-1:0])
                    & ~aw_id_stall[gm] & ~wdest_full[gm];
                assign ar_arbin_valid[gt][gm] =
                    ar_valid_skd[gm] & (ar_sel[gm] == gt[SELECT_WIDTH-1:0])
                    & ~ar_id_stall[gm];
            end
        end
    endgenerate

    //================ PER-SLOT AW / AR ARBITERS =====================
    generate
        for (gt = 0; gt < NUM_TARGETS; gt++) begin : g_arb
            // candidate payloads for THIS slot, one entry per master
            logic [ID_WIDTH-1:0]      awid_c   [0:NUM_MASTERS-1];
            logic [ADDRESS_WIDTH-1:0] awaddr_c [0:NUM_MASTERS-1];
            logic [LEN_WIDTH-1:0]     awlen_c  [0:NUM_MASTERS-1];
            logic [QOS_WIDTH-1:0]     awqos_c  [0:NUM_MASTERS-1];
            logic [ID_WIDTH-1:0]      arid_c   [0:NUM_MASTERS-1];
            logic [ADDRESS_WIDTH-1:0] araddr_c [0:NUM_MASTERS-1];
            logic [LEN_WIDTH-1:0]     arlen_c  [0:NUM_MASTERS-1];
            logic [QOS_WIDTH-1:0]     arqos_c  [0:NUM_MASTERS-1];

            for (gm = 0; gm < NUM_MASTERS; gm++) begin : g_cand
                assign awid_c  [gm] = awid_tag  [gm];
                assign awaddr_c[gm] = awaddr_skd[gm];
                assign awlen_c [gm] = awlen_skd [gm];
                assign awqos_c [gm] = awqos_skd[gm];
                assign arid_c  [gm] = arid_tag  [gm];
                assign araddr_c[gm] = araddr_skd[gm];
                assign arlen_c [gm] = arlen_skd [gm];
                assign arqos_c [gm] = arqos_skd [gm];
            end

            addr_arbiter #(.NM(NUM_MASTERS), .MW(MW)) u_awarb (
                .ACLK(ACLK), .ARESETn(ARESETn),
                .arbin_valid (aw_arbin_valid[gt]),
                .arbin_ready (aw_arbin_ready[gt]),
                .id_i        (awid_c),
                .addr_i      (awaddr_c),
                .len_i       (awlen_c),
                .qos_i       (awqos_c),
                .id_o        (aw_id[gt]),
                .addr_o      (aw_addr[gt]),
                .len_o       (aw_len[gt]),
                .qos_o       (aw_qos[gt]),
                .arbout_valid(aw_arbout_valid[gt]),
                .arbout_ready(aw_arbout_ready[gt]),
                .grant_valid (aw_grant_valid[gt]),
                .grant_idx   (aw_grant_idx[gt])
            );

            addr_arbiter #(.NM(NUM_MASTERS), .MW(MW)) u_ararb (
                .ACLK(ACLK), .ARESETn(ARESETn),
                .arbin_valid (ar_arbin_valid[gt]),
                .arbin_ready (ar_arbin_ready[gt]),
                .id_i        (arid_c),
                .addr_i      (araddr_c),
                .len_i       (arlen_c),
                .qos_i       (arqos_c),
                .id_o        (ar_id[gt]),
                .addr_o      (ar_addr[gt]),
                .len_o       (ar_len[gt]),
                .qos_o       (ar_qos[gt]),
                .arbout_valid(ar_arbout_valid[gt]),
                .arbout_ready(ar_arbout_ready[gt]),
                .grant_valid (ar_grant_valid[gt]),
                .grant_idx   (ar_grant_idx[gt])
            );
        end
    endgenerate

    //================ W ROUTING INTERLOCK + MUX =====================
    generate
        for (gt = 0; gt < NUM_TARGETS; gt++) begin : g_wmux
            // owning master of the burst slot gt is currently accepting
            wire [MW-1:0] om = w_owner[gt][MW-1:0];
            wire agree = w_owner_valid[gt]
                       & ~wdest_empty[om]
                       & (wdest_head[om] == gt[SELECT_WIDTH-1:0]);
            assign w_data[gt]         = wdata_skd[om];
            assign w_strb[gt]         = wstrb_skd[om];
            assign w_last[gt]         = wlast_skd[om];
            assign w_arbout_valid[gt] = agree & w_valid_skd[om];
        end
    endgenerate

    //================ READY FAN-BACK TO MASTERS =====================
    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            aw_ready_skd[m] = 1'b0;
            ar_ready_skd[m] = 1'b0;
            w_ready_skd [m] = 1'b0;
            for (int s = 0; s < NUM_TARGETS; s++) begin
                if (aw_arbin_ready[s][m]) aw_ready_skd[m] = 1'b1;
                if (ar_arbin_ready[s][m]) ar_ready_skd[m] = 1'b1;
                if (w_owner_valid[s] &&
                    (w_owner[s][MW-1:0] == m[MW-1:0]) &&
                    !wdest_empty[m] && (wdest_head[m] == s[SELECT_WIDTH-1:0]) &&
                    w_arbout_ready[s])
                    w_ready_skd[m] = 1'b1;
            end
        end
    end

    //================ W-DESTINATION FIFO PUSH / POP =================
    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            wdest_push     [m] = 1'b0;
            wdest_push_slot[m] = '0;
            wdest_pop      [m] = 1'b0;
            for (int s = 0; s < NUM_TARGETS; s++) begin
                if (aw_grant_valid[s] && (aw_grant_idx[s] == m[MW-1:0])) begin
                    wdest_push     [m] = 1'b1;
                    wdest_push_slot[m] = s[SELECT_WIDTH-1:0];
                end
                if (w_burst_end[s] && (w_owner[s][MW-1:0] == m[MW-1:0]))
                    wdest_pop[m] = 1'b1;
            end
        end
    end

    //================ B / R READY OR ACROSS MASTERS =================
    generate
        for (gt = 0; gt < NUM_TARGETS; gt++) begin : g_retor
            assign b_ready_s[gt] = |b_ready_bits[gt];
            assign r_ready_s[gt] = |r_ready_bits[gt];
        end
    endgenerate

    //================ ID SCOREBOARD UPDATE ==========================
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            aw_id_busy <= '0;
            ar_id_busy <= '0;
        end else begin
            // retire first, then issue: a same-id issue in the same cycle wins
            for (int m = 0; m < NUM_MASTERS; m++) begin
                if (b_retire[m]) aw_id_busy[b_retire_id[m]] <= 1'b0;
                if (r_retire[m]) ar_id_busy[r_retire_id[m]] <= 1'b0;
            end
            for (int s = 0; s < NUM_TARGETS; s++) begin
                if (aw_grant_valid[s]) aw_id_busy[aw_id[s]] <= 1'b1;
                if (ar_grant_valid[s]) ar_id_busy[ar_id[s]] <= 1'b1;
            end
        end
    end

    //================ MASTER INTERFACES =============================
    generate
        for (gm = 0; gm < NUM_MASTERS; gm++) begin : g_master
            logic [NUM_TARGETS-1:0] bready_m;
            logic [NUM_TARGETS-1:0] rready_m;

            master #(.MASTER_IDX(gm), .NT(NUM_TARGETS)) u_master (
                .ACLK(ACLK), .ARESETn(ARESETn),

                .AWID(AWID[gm]), .AWADDR(AWADDR[gm]), .AWLEN(AWLEN[gm]),
                .AWBURST(AWBURST[gm]), .AWQOS(AWQOS[gm]),
                .AWVALID(AWVALID[gm]), .AWREADY(awready_i[gm]),
                .awid_tag_o(awid_tag[gm]), .awaddr_skd_o(awaddr_skd[gm]),
                .awlen_skd_o(awlen_skd[gm]), .awqos_skd_o(awqos_skd[gm]),
                .aw_sel_o(aw_sel[gm]),
                .aw_valid_skd_o(aw_valid_skd[gm]), .aw_ready_skd_i(aw_ready_skd[gm]),

                .WDATA(WDATA[gm]), .WSTRB(WSTRB[gm]), .WLAST(WLAST[gm]),
                .WVALID(WVALID[gm]), .WREADY(wready_i[gm]),
                .wdata_skd_o(wdata_skd[gm]), .wstrb_skd_o(wstrb_skd[gm]),
                .wlast_skd_o(wlast_skd[gm]),
                .w_valid_skd_o(w_valid_skd[gm]), .w_ready_skd_i(w_ready_skd[gm]),

                .wdest_push_i(wdest_push[gm]), .wdest_push_slot_i(wdest_push_slot[gm]),
                .wdest_pop_i(wdest_pop[gm]),
                .wdest_head_o(wdest_head[gm]), .wdest_empty_o(wdest_empty[gm]),
                .wdest_full_o(wdest_full[gm]),

                .b_id_s_i(b_id_s), .b_resp_s_i(b_resp_s), .b_qos_s_i(b_qos_s),
                .b_valid_s_i(b_valid_s),
                .b_ready_s_o(bready_m),
                .BID(bid_i[gm]), .BRESP(bresp_i[gm]), .BVALID(bvalid_i[gm]), .BREADY(BREADY[gm]),

                .ARID(ARID[gm]), .ARADDR(ARADDR[gm]), .ARLEN(ARLEN[gm]),
                .ARBURST(ARBURST[gm]), .ARQOS(ARQOS[gm]),
                .ARVALID(ARVALID[gm]), .ARREADY(arready_i[gm]),
                .arid_tag_o(arid_tag[gm]), .araddr_skd_o(araddr_skd[gm]),
                .arlen_skd_o(arlen_skd[gm]), .arqos_skd_o(arqos_skd[gm]),
                .ar_sel_o(ar_sel[gm]),
                .ar_valid_skd_o(ar_valid_skd[gm]), .ar_ready_skd_i(ar_ready_skd[gm]),

                .r_id_s_i(r_id_s), .r_data_s_i(r_data_s), .r_resp_s_i(r_resp_s),
                .r_qos_s_i(r_qos_s),
                .r_last_s_i(r_last_s), .r_valid_s_i(r_valid_s),
                .r_ready_s_o(rready_m),
                .RID(rid_i[gm]), .RDATA(rdata_i[gm]), .RRESP(rresp_i[gm]),
                .RLAST(rlast_i[gm]), .RVALID(rvalid_i[gm]), .RREADY(RREADY[gm]),

                .b_retire_o(b_retire[gm]), .b_retire_id_o(b_retire_id[gm]),
                .r_retire_o(r_retire[gm]), .r_retire_id_o(r_retire_id[gm])
            );

            for (gu = 0; gu < NUM_TARGETS; gu++) begin : g_ret_unpack
                assign b_ready_bits[gu][gm] = bready_m[gu];
                assign r_ready_bits[gu][gm] = rready_m[gu];
            end
        end
    endgenerate

    generate
        for (gm = 0; gm < NUM_MASTERS; gm++) begin : g_outmap
            assign AWREADY[gm] = awready_i[gm];
            assign WREADY [gm] = wready_i [gm];
            assign BID    [gm] = bid_i    [gm];
            assign BRESP  [gm] = bresp_i  [gm];
            assign BVALID [gm] = bvalid_i [gm];
            assign ARREADY[gm] = arready_i[gm];
            assign RID    [gm] = rid_i    [gm];
            assign RDATA  [gm] = rdata_i  [gm];
            assign RRESP  [gm] = rresp_i  [gm];
            assign RLAST  [gm] = rlast_i  [gm];
            assign RVALID [gm] = rvalid_i [gm];
        end
    endgenerate

    //================ SLAVE INTERFACES ==============================
    //logic [SLAVE_REG_COUNT*DATA_WIDTH-1:0] dbg [0:NUM_SLAVES-1];

    generate
        for (gt = 0; gt < NUM_SLAVES; gt++) begin : g_slv
            slave #(.BASE_ADDR(SLAVE_BASE_FLAT[gt*ADDRESS_WIDTH +: ADDRESS_WIDTH])) u_slave (
                .ACLK(ACLK), .ARESETn(ARESETn),
                .AWID_I(aw_id[gt]), .AWADDR_I(aw_addr[gt]), .AWLEN_I(aw_len[gt]),
                .AWQOS_I(aw_qos[gt]),
                .AWVALID_I(aw_arbout_valid[gt]), .AWREADY_O(aw_arbout_ready[gt]),
                .WDATA_I(w_data[gt]), .WSTRB_I(w_strb[gt]), .WLAST_I(w_last[gt]),
                .WVALID_I(w_arbout_valid[gt]), .WREADY_O(w_arbout_ready[gt]),
                .BID_O(b_id_s[gt]), .BRESP_O(b_resp_s[gt]), .b_qos_o(b_qos_s[gt]),
                .BVALID_O(b_valid_s[gt]), .BREADY_I(b_ready_s[gt]),
                .ARID_I(ar_id[gt]), .ARADDR_I(ar_addr[gt]), .ARLEN_I(ar_len[gt]),
                .ARQOS_I(ar_qos[gt]),
                .ARVALID_I(ar_arbout_valid[gt]), .ARREADY_O(ar_arbout_ready[gt]),
                .RID_O(r_id_s[gt]), .RDATA_O(r_data_s[gt]), .RRESP_O(r_resp_s[gt]),
                .r_qos_o(r_qos_s[gt]),
                .RLAST_O(r_last_s[gt]), .RVALID_O(r_valid_s[gt]), .RREADY_I(r_ready_s[gt]),
                .w_owner_o(w_owner[gt]), .w_owner_valid_o(w_owner_valid[gt]),
                .w_burst_end_o(w_burst_end[gt]),
                .regs_we_o   (REGS_WE[gt]),
                .regs_waddr_o(REGS_WADDR[gt]),
                .regs_wdata_o(REGS_WDATA[gt]),
                .regs_wstrb_o(REGS_WSTRB[gt]),
                .regs_raddr_o(REGS_RADDR[gt]),
                .regs_rdata_i(REGS_RDATA[gt])
            );
        end
    endgenerate

    // The error target keeps no QoS state
    assign b_qos_s[NUM_SLAVES] = '0;
    assign r_qos_s[NUM_SLAVES] = '0;

    err_slave u_err_slave (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWID_I(aw_id[NUM_SLAVES]), .AWLEN_I(aw_len[NUM_SLAVES]),
        .AWVALID_I(aw_arbout_valid[NUM_SLAVES]), .AWREADY_O(aw_arbout_ready[NUM_SLAVES]),
        .WLAST_I(w_last[NUM_SLAVES]),
        .WVALID_I(w_arbout_valid[NUM_SLAVES]), .WREADY_O(w_arbout_ready[NUM_SLAVES]),
        .BID_O(b_id_s[NUM_SLAVES]), .BRESP_O(b_resp_s[NUM_SLAVES]),
        .BVALID_O(b_valid_s[NUM_SLAVES]), .BREADY_I(b_ready_s[NUM_SLAVES]),
        .ARID_I(ar_id[NUM_SLAVES]), .ARLEN_I(ar_len[NUM_SLAVES]),
        .ARVALID_I(ar_arbout_valid[NUM_SLAVES]), .ARREADY_O(ar_arbout_ready[NUM_SLAVES]),
        .RID_O(r_id_s[NUM_SLAVES]), .RDATA_O(r_data_s[NUM_SLAVES]), .RRESP_O(r_resp_s[NUM_SLAVES]),
        .RLAST_O(r_last_s[NUM_SLAVES]), .RVALID_O(r_valid_s[NUM_SLAVES]), .RREADY_I(r_ready_s[NUM_SLAVES]),
        .w_owner_o(w_owner[NUM_SLAVES]), .w_owner_valid_o(w_owner_valid[NUM_SLAVES]),
        .w_burst_end_o(w_burst_end[NUM_SLAVES])
    );

endmodule
