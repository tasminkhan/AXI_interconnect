//   AW : testbench -> [skid] -> fabric      (payload {ID,ADDR,LEN,BURST})
//   W  : testbench -> [skid] -> fabric      (payload {DATA,STRB,LAST})
//   B  : fabric    -> [skid] -> testbench   (payload {ID,RESP})
import param_pkg::*;

module master (
    input  logic                      ACLK,
    input  logic                      ARESETn,

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
    input  logic                      BREADY
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

endmodule