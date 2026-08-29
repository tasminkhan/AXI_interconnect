//   AW : testbench -> [skid] -> fabric      (payload {ID,ADDR,LEN,BURST})
//   W  : testbench -> [skid] -> fabric      (payload {DATA,STRB,LAST})
//   B  : fabric    -> [skid] -> testbench   (payload {ID,RESP})
import param_pkg::*;

module master (
    input  logic                      ACLK,
    input 
     logic                      ARESETn,

    //================ AW channel : testbench side =====================
    input  logic [ID_WIDTH-1:0]       AWID,
    input  logic [ADDRESS_WIDTH-1:0]  AWADDR,
    input  logic [LEN_WIDTH-1:0]      AWLEN,
    input  logic [BURST_WIDTH-1:0]    AWBURST,
    input  logic                      AWVALID,
    output logic                      AWREADY,        // registered (skid input ready)

    //================ AW channel : fabric side (to decoder/demux) =====
    output logic [ID_WIDTH-1:0]       AWID_SKD,
    output logic [ADDRESS_WIDTH-1:0]  AWADDR_SKD,
    output logic [LEN_WIDTH-1:0]      AWLEN_SKD,
    output logic [BURST_WIDTH-1:0]    AWBURST_SKD,
    output logic                      AWVALID_DMUX,
    input  logic                      AWREADY_MUX,    // release-ready from AW ready-mux

    //================ W channel : testbench side ======================
    input  logic [DATA_WIDTH-1:0]     WDATA,
    input  logic [STROBE_WIDTH-1:0]   WSTRB,
    input  logic                      WLAST,
    input  logic                      WVALID,
    output logic                      WREADY,         // registered (skid input ready)

    //================ W channel : fabric side (to W demux) ============
    output logic [DATA_WIDTH-1:0]     WDATA_SKD,
    output logic [STROBE_WIDTH-1:0]   WSTRB_SKD,
    output logic                      WLAST_SKD,
    output logic                      WVALID_DMUX,
    input  logic                      WREADY_MUX,     // release-ready from W ready-mux

    //================ B channel : fabric side (from response mux) =====
    input  logic [ID_WIDTH-1:0]       BID_MUX,
    input  logic [RESP_WIDTH-1:0]     BRESP_MUX,
    input  logic                      BVALID_MUX,
    output logic                      BREADY_DMUX,    // registered (B skid input ready)

    //================ B channel : testbench side ======================
    output logic [ID_WIDTH-1:0]       BID,
    output logic [RESP_WIDTH-1:0]     BRESP,
    output logic                      BVALID,
    input  logic                      BREADY,

    //================ AR channel : testbench side =====================
    input  logic [ID_WIDTH-1:0]       ARID,
    input  logic [ADDRESS_WIDTH-1:0]  ARADDR,
    input  logic [LEN_WIDTH-1:0]      ARLEN,
    input  logic [BURST_WIDTH-1:0]    ARBURST,
    input  logic [QOS_WIDTH-1:0]      ARQOS,
    input  logic                      ARVALID,
    output logic                      ARREADY,

    //================ AR channel : fabric side ========================
    output logic [ID_WIDTH-1:0]       ARID_SKD,
    output logic [ADDRESS_WIDTH-1:0]  ARADDR_SKD,
    output logic [LEN_WIDTH-1:0]      ARLEN_SKD,
    output logic [BURST_WIDTH-1:0]    ARBURST_SKD,
    output  logic [QOS_WIDTH-1:0]     ARQOS_SKD,
    output logic                      ARVALID_DMUX,
    input  logic                      ARREADY_MUX,

    //================ R channel : fabric side (from read mux) =========
    input  logic [ID_WIDTH-1:0]       RID_MUX,
    input  logic [DATA_WIDTH-1:0]     RDATA_MUX,
    input  logic [RESP_WIDTH-1:0]     RRESP_MUX,
    input  logic                      RLAST_MUX,
    input  logic                      RVALID_MUX,
    output logic                      RREADY_DMUX,

    //================ R channel : testbench side ======================
    output logic [ID_WIDTH-1:0]       RID,
    output logic [DATA_WIDTH-1:0]     RDATA,
    output logic [RESP_WIDTH-1:0]     RRESP,
    output logic                      RLAST,
    output logic                      RVALID,
    input  logic                      RREADY
);

    //-----------------------------------------------------------------
    // AW skid buffer : pack {ID, ADDR, LEN, BURST} = 18 bits
    //-----------------------------------------------------------------
    logic [AW_PAYLOAD_WIDTH-1:0] aw_pack_in, aw_pack_out;
    assign aw_pack_in = {AWID, AWADDR, AWLEN, AWBURST};
    assign {AWID_SKD, AWADDR_SKD, AWLEN_SKD, AWBURST_SKD} = aw_pack_out;

    skidbuffer #(.WIDTH(AW_PAYLOAD_WIDTH)) u_aw_skid (
        .clk       (ACLK),
        .rst_n     (ARESETn),
        .in_data   (aw_pack_in),
        .in_valid  (AWVALID),
        .in_ready  (AWREADY),        // what the testbench handshakes against
        .out_data  (aw_pack_out),
        .out_valid (AWVALID_DMUX),
        .out_ready (AWREADY_MUX)
    );

    //-----------------------------------------------------------------
    // W skid buffer : pack {DATA, STRB, LAST} = 19 bits
    //-----------------------------------------------------------------
    logic [W_PAYLOAD_WIDTH-1:0] w_pack_in, w_pack_out;
    assign w_pack_in = {WDATA, WSTRB, WLAST};
    assign {WDATA_SKD, WSTRB_SKD, WLAST_SKD} = w_pack_out;

    skidbuffer #(.WIDTH(W_PAYLOAD_WIDTH)) u_w_skid (
        .clk       (ACLK),
        .rst_n     (ARESETn),
        .in_data   (w_pack_in),
        .in_valid  (WVALID),
        .in_ready  (WREADY),
        .out_data  (w_pack_out),
        .out_valid (WVALID_DMUX),
        .out_ready (WREADY_MUX)
    );

    //-----------------------------------------------------------------
    // B skid buffer : return direction. Input side faces the response
    // mux (fabric); output side faces the testbench.
    // Pack {ID, RESP} = 6 bits.
    //-----------------------------------------------------------------
    logic [B_PAYLOAD_WIDTH-1:0] b_pack_in, b_pack_out;
    assign b_pack_in = {BID_MUX, BRESP_MUX};
    assign {BID, BRESP} = b_pack_out;

    skidbuffer #(.WIDTH(B_PAYLOAD_WIDTH)) u_b_skid (
        .clk       (ACLK),
        .rst_n     (ARESETn),
        .in_data   (b_pack_in),
        .in_valid  (BVALID_MUX),
        .in_ready  (BREADY_DMUX),     // fabric-side ready; select-FIFO pops on this handshake
        .out_data  (b_pack_out),
        .out_valid (BVALID),
        .out_ready (BREADY)
    );
    
    //-----------------------------------------------------------------
    // AR skid buffer : pack {ID, ADDR, LEN, BURST} (same width as AW)
    //-----------------------------------------------------------------
    logic [AR_PAYLOAD_WIDTH-1:0] ar_pack_in, ar_pack_out;
    assign ar_pack_in = {ARID, ARADDR, ARLEN, ARBURST, ARQOS};
    assign {ARID_SKD, ARADDR_SKD, ARLEN_SKD, ARBURST_SKD, ARQOS_SKD} = ar_pack_out;

    skidbuffer #(.WIDTH(AR_PAYLOAD_WIDTH)) u_ar_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(ar_pack_in), .in_valid(ARVALID), .in_ready(ARREADY),
        .out_data(ar_pack_out), .out_valid(ARVALID_DMUX), .out_ready(ARREADY_MUX)
    );

    //-----------------------------------------------------------------
    // R skid buffer : return direction. Pack {ID, DATA, RESP, LAST}
    //-----------------------------------------------------------------
    localparam int R_PAYLOAD_WIDTH = ID_WIDTH + DATA_WIDTH + RESP_WIDTH + 1;
    logic [R_PAYLOAD_WIDTH-1:0] r_pack_in, r_pack_out;
    assign r_pack_in = {RID_MUX, RDATA_MUX, RRESP_MUX, RLAST_MUX};
    assign {RID, RDATA, RRESP, RLAST} = r_pack_out;

    skidbuffer #(.WIDTH(R_PAYLOAD_WIDTH)) u_r_skid (
        .clk(ACLK), .rst_n(ARESETn),
        .in_data(r_pack_in), .in_valid(RVALID_MUX), .in_ready(RREADY_DMUX),
        .out_data(r_pack_out), .out_valid(RVALID), .out_ready(RREADY)
    );

endmodule