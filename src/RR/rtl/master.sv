`timescale 1ns / 1ps
import param_pkg::*;

module master #(
    parameter int MASTER_IDX = 0,
    parameter int NT         = NUM_TARGETS
)(
    input  logic ACLK,
    input  logic ARESETn,

    //================ AW : testbench side ============================
    input  logic [ORIG_ID_WIDTH-1:0]  AWID,
    input  logic [ADDRESS_WIDTH-1:0]  AWADDR,
    input  logic [LEN_WIDTH-1:0]      AWLEN,
    input  logic [BURST_WIDTH-1:0]    AWBURST,
    input  logic [QOS_WIDTH-1:0]      AWQOS,
    input  logic                      AWVALID,
    output logic                      AWREADY,

    //================ AW : fabric side ===============================
    output logic [ID_WIDTH-1:0]       awid_tag_o,      // tagged id
    output logic [ADDRESS_WIDTH-1:0]  awaddr_skd_o,
    output logic [LEN_WIDTH-1:0]      awlen_skd_o,
    output logic [QOS_WIDTH-1:0]      awqos_skd_o,
    output logic [SELECT_WIDTH-1:0]   aw_sel_o,        // decoded target slot
    output logic                      aw_valid_skd_o,
    input  logic                      aw_ready_skd_i,

    //================ W : testbench side =============================
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [STROBE_WIDTH-1:0]   WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,

    //================ W : fabric side ================================
    output logic [DATA_WIDTH-1:0]     wdata_skd_o,
    output logic [STROBE_WIDTH-1:0]   wstrb_skd_o,
    output logic                      wlast_skd_o,
    output logic                      w_valid_skd_o,
    input  logic                      w_ready_skd_i,

    //================ W-DESTINATION FIFO (per master) ================
    input  logic                      wdest_push_i,      // this master granted
    input  logic [SELECT_WIDTH-1:0]   wdest_push_slot_i, // ...at this slot
    input  logic                      wdest_pop_i,       // its head slot ended a burst
    output logic [SELECT_WIDTH-1:0]   wdest_head_o,
    output logic                      wdest_empty_o,
    output logic                      wdest_full_o,

    //================ B : per-slot inputs (all slaves) ===============
    input  logic [ID_WIDTH-1:0]       b_id_s_i    [0:NT-1],
    input  logic [RESP_WIDTH-1:0]     b_resp_s_i  [0:NT-1],
    input  logic                      b_valid_s_i [0:NT-1],
    output logic [NT-1:0]             b_ready_s_o,

    //================ B : testbench side =============================
    output logic [ORIG_ID_WIDTH-1:0]  BID,
    output logic [RESP_WIDTH-1:0]     BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    //================ AR : testbench side ============================
    input  logic [ORIG_ID_WIDTH-1:0]  ARID,
    input  logic [ADDRESS_WIDTH-1:0]  ARADDR,
    input  logic [LEN_WIDTH-1:0]      ARLEN,
    input  logic [BURST_WIDTH-1:0]    ARBURST,
    input  logic [QOS_WIDTH-1:0]      ARQOS,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    //================ AR : fabric side ===============================
    output logic [ID_WIDTH-1:0]       arid_tag_o,
    output logic [ADDRESS_WIDTH-1:0]  araddr_skd_o,
    output logic [LEN_WIDTH-1:0]      arlen_skd_o,
    output logic [QOS_WIDTH-1:0]      arqos_skd_o,
    output logic [SELECT_WIDTH-1:0]   ar_sel_o,
    output logic                      ar_valid_skd_o,
    input  logic                      ar_ready_skd_i,

    //================ R : per-slot inputs (all slaves) ===============
    input  logic [ID_WIDTH-1:0]       r_id_s_i    [0:NT-1],
    input  logic [DATA_WIDTH-1:0]     r_data_s_i  [0:NT-1],
    input  logic [RESP_WIDTH-1:0]     r_resp_s_i  [0:NT-1],
    input  logic                      r_last_s_i  [0:NT-1],
    input  logic                      r_valid_s_i [0:NT-1],
    output logic [NT-1:0]             r_ready_s_o,

    //================ R : testbench side =============================
    output logic [ORIG_ID_WIDTH-1:0]  RID,
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [RESP_WIDTH-1:0]     RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY,

    //================ retire pulses (to the top's scoreboard) ========
    output logic                      b_retire_o,
    output logic [ID_WIDTH-1:0]       b_retire_id_o,
    output logic                      r_retire_o,
    output logic [ID_WIDTH-1:0]       r_retire_id_o
);
    //-----------------------------------------------------------------
    // AW skid : {orig id, addr, len, burst}
    //-----------------------------------------------------------------
    localparam int AWP = ORIG_ID_WIDTH + ADDRESS_WIDTH + LEN_WIDTH + BURST_WIDTH + QOS_WIDTH;
    logic [AWP-1:0]           aw_pack_in, aw_pack_out;
    logic [ORIG_ID_WIDTH-1:0] awid_skd;
    logic [BURST_WIDTH-1:0]   awburst_skd;

    assign aw_pack_in = {AWID, AWADDR, AWLEN, AWBURST, AWQOS};
    assign {awid_skd, awaddr_skd_o, awlen_skd_o, awburst_skd, awqos_skd_o} = aw_pack_out;

    skidbuffer #(.WIDTH(AWP)) u_aw_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(aw_pack_in), .in_valid(AWVALID), .in_ready(AWREADY),
        .out_data(aw_pack_out), .out_valid(aw_valid_skd_o), .out_ready(aw_ready_skd_i)
    );

    //-----------------------------------------------------------------
    // W skid : {data, strb, last}
    //-----------------------------------------------------------------
    logic [W_PAYLOAD_WIDTH-1:0] w_pack_in, w_pack_out;
    assign w_pack_in = {WDATA, WSTRB, WLAST};
    assign {wdata_skd_o, wstrb_skd_o, wlast_skd_o} = w_pack_out;

    skidbuffer #(.WIDTH(W_PAYLOAD_WIDTH)) u_w_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(w_pack_in), .in_valid(WVALID), .in_ready(WREADY),
        .out_data(w_pack_out), .out_valid(w_valid_skd_o), .out_ready(w_ready_skd_i)
    );

    //-----------------------------------------------------------------
    // AR skid : {orig id, addr, len, burst, qos}
    //-----------------------------------------------------------------
    localparam int ARP = ORIG_ID_WIDTH + ADDRESS_WIDTH + LEN_WIDTH + BURST_WIDTH + QOS_WIDTH;
    logic [ARP-1:0]           ar_pack_in, ar_pack_out;
    logic [ORIG_ID_WIDTH-1:0] arid_skd;
    logic [BURST_WIDTH-1:0]   arburst_skd;

    assign ar_pack_in = {ARID, ARADDR, ARLEN, ARBURST, ARQOS};
    assign {arid_skd, araddr_skd_o, arlen_skd_o, arburst_skd, arqos_skd_o} = ar_pack_out;

    skidbuffer #(.WIDTH(ARP)) u_ar_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(ar_pack_in), .in_valid(ARVALID), .in_ready(ARREADY),
        .out_data(ar_pack_out), .out_valid(ar_valid_skd_o), .out_ready(ar_ready_skd_i)
    );

    //-----------------------------------------------------------------
    // ID TAGGING : high bits = this master's index
    //-----------------------------------------------------------------
    assign awid_tag_o = { MASTER_IDX[MASTER_TAG_WIDTH-1:0], awid_skd };
    assign arid_tag_o = { MASTER_IDX[MASTER_TAG_WIDTH-1:0], arid_skd };

    //-----------------------------------------------------------------
    // ADDRESS DECODE : which target slot this master is addressing
    //-----------------------------------------------------------------
    addr_decoder u_awdec (
        .ADDR_SKD  (awaddr_skd_o),
        .LEN_SKD   (awlen_skd_o),
        .BURST_SKD (awburst_skd),
        .sel       (aw_sel_o)
    );

    addr_decoder u_ardec (
        .ADDR_SKD  (araddr_skd_o),
        .LEN_SKD   (arlen_skd_o),
        .BURST_SKD (arburst_skd),
        .sel       (ar_sel_o)
    );
    //-----------------------------------------------------------------
    // W-DESTINATION FIFO : in AW-issue order, the slot each write goes
    // to. Head = where this master's current W burst must be delivered.
    //-----------------------------------------------------------------
    logic [SELECT_WIDTH-1:0]     wdest_mem [0:SELECT_FIFO_DEPTH-1];
    logic [SELECT_PTR_WIDTH-1:0] wdest_wp, wdest_rp;

    assign wdest_empty_o = (wdest_wp == wdest_rp);
    assign wdest_full_o  = (wdest_wp[SELECT_PTR_WIDTH-2:0] == wdest_rp[SELECT_PTR_WIDTH-2:0])
                         & (wdest_wp[SELECT_PTR_WIDTH-1]   != wdest_rp[SELECT_PTR_WIDTH-1]);
    assign wdest_head_o  = wdest_mem[wdest_rp[SELECT_PTR_WIDTH-2:0]];

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            wdest_wp <= '0; wdest_rp <= '0;
        end else begin
            if (wdest_push_i && !wdest_full_o) begin
                wdest_mem[wdest_wp[SELECT_PTR_WIDTH-2:0]] <= wdest_push_slot_i;
                wdest_wp <= wdest_wp + 1'b1;
            end
            if (wdest_pop_i && !wdest_empty_o)
                wdest_rp <= wdest_rp + 1'b1;
        end
    end

    //-----------------------------------------------------------------
    // RETURN PATH : per-master B and R arbiters. 
    //-----------------------------------------------------------------
    logic [ID_WIDTH-1:0]   b_id_arb;
    logic [RESP_WIDTH-1:0] b_resp_arb;
    logic                  b_valid_arb, b_ready_arb;

    b_arbiter #(.MASTER_ID(MASTER_IDX), .NT(NT)) u_barb (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .b_id_s_i   (b_id_s_i),
        .b_resp_s_i (b_resp_s_i),
        .b_valid_s_i(b_valid_s_i),
        .b_ready_s_o(b_ready_s_o),
        .b_id_o   (b_id_arb),
        .b_resp_o (b_resp_arb),
        .b_valid_o(b_valid_arb),
        .b_ready_i(b_ready_arb)
    );

    logic [ID_WIDTH-1:0]   r_id_arb;
    logic [DATA_WIDTH-1:0] r_data_arb;
    logic [RESP_WIDTH-1:0] r_resp_arb;
    logic                  r_last_arb, r_valid_arb, r_ready_arb;

    r_arbiter #(.MASTER_ID(MASTER_IDX), .NT(NT)) u_rarb (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .r_id_s_i   (r_id_s_i),
        .r_data_s_i (r_data_s_i),
        .r_resp_s_i (r_resp_s_i),
        .r_last_s_i (r_last_s_i),
        .r_valid_s_i(r_valid_s_i),
        .r_ready_s_o(r_ready_s_o),
        .r_id_o   (r_id_arb),
        .r_data_o (r_data_arb),
        .r_resp_o (r_resp_arb),
        .r_last_o (r_last_arb),
        .r_valid_o(r_valid_arb),
        .r_ready_i(r_ready_arb)
    );

    //-----------------------------------------------------------------
    // B skid : fabric -> testbench. the master's original id is returned.
    //-----------------------------------------------------------------
    localparam int BP = ORIG_ID_WIDTH + RESP_WIDTH;
    logic [BP-1:0] b_pack_in, b_pack_out;
    assign b_pack_in = { b_id_arb[ORIG_ID_WIDTH-1:0], b_resp_arb };
    assign {BID, BRESP} = b_pack_out;

    skidbuffer #(.WIDTH(BP)) u_b_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(b_pack_in), .in_valid(b_valid_arb), .in_ready(b_ready_arb),
        .out_data(b_pack_out), .out_valid(BVALID), .out_ready(BREADY)
    );

    //-----------------------------------------------------------------
    // R skid : fabric -> testbench, tag stripped.
    //-----------------------------------------------------------------
    localparam int RP = ORIG_ID_WIDTH + DATA_WIDTH + RESP_WIDTH + 1;
    logic [RP-1:0] r_pack_in, r_pack_out;
    assign r_pack_in = { r_id_arb[ORIG_ID_WIDTH-1:0], r_data_arb, r_resp_arb, r_last_arb };
    assign {RID, RDATA, RRESP, RLAST} = r_pack_out;

    skidbuffer #(.WIDTH(RP)) u_r_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(r_pack_in), .in_valid(r_valid_arb), .in_ready(r_ready_arb),
        .out_data(r_pack_out), .out_valid(RVALID), .out_ready(RREADY)
    );

    //-----------------------------------------------------------------
    // RETIRE PULSES 
    //-----------------------------------------------------------------
    assign b_retire_o    = b_valid_arb & b_ready_arb;
    assign b_retire_id_o = b_id_arb;
    assign r_retire_o    = r_valid_arb & r_ready_arb & r_last_arb;
    assign r_retire_id_o = r_id_arb;

endmodule
