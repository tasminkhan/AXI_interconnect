//=====================================================================
// axi_pkg.sv - shared parameters. Import with:  import axi_pkg::*;
// BEFORE the module port list, so port widths can use them.
//=====================================================================
package param_pkg;

    //------------------ fundamental (SET) -----------------------
    localparam int DATA_WIDTH    = 16;
    localparam int ADDRESS_WIDTH = 8;
    localparam int ID_WIDTH      = 4;
    localparam int LEN_WIDTH     = 4;

    //------------------ priority things -------------------------
    localparam int QOS_WIDTH = 4;                  // priority value width
    localparam int AGE_WIDTH = 4;                  // starvation age counter width
    localparam logic [QOS_WIDTH-1:0] QOS_MAX      = {QOS_WIDTH{1'b1}};
    localparam logic [AGE_WIDTH-1:0] STARVE_LIMIT = 4'd8;
    
    //------------------ spec-fixed constants --------------------
    localparam int BURST_WIDTH   = 2;
    localparam int RESP_WIDTH    = 2;

    //------------------ derived widths --------------------------
    localparam int STROBE_WIDTH     = DATA_WIDTH/8;
    localparam int AW_PAYLOAD_WIDTH = ID_WIDTH+ADDRESS_WIDTH+LEN_WIDTH+BURST_WIDTH;
    localparam int AR_PAYLOAD_WIDTH = AW_PAYLOAD_WIDTH + QOS_WIDTH;
    localparam int W_PAYLOAD_WIDTH  = DATA_WIDTH+STROBE_WIDTH+1;
    localparam int B_PAYLOAD_WIDTH  = ID_WIDTH+RESP_WIDTH;

    //------------------ capacity/structure (SET) ----------------
    localparam int OUTSTANDING       = 4;
    localparam int NUM_SLAVES        = 2;
    localparam int SLAVE_FIFO_DEPTH  = 4;
    localparam int SELECT_FIFO_DEPTH = OUTSTANDING;   // now DERIVED
    localparam int SLAVE_REG_COUNT   = 16;

    //------------------ derived ---------------------------------
    localparam int NUM_TARGETS      = NUM_SLAVES + 1;
    localparam int SELECT_WIDTH     = $clog2(NUM_TARGETS);
    localparam int SLAVE_PTR_WIDTH  = $clog2(SLAVE_FIFO_DEPTH) + 1;
    localparam int SELECT_PTR_WIDTH = $clog2(SELECT_FIFO_DEPTH) + 1;
    localparam int BEAT_COUNT_WIDTH = LEN_WIDTH;
    localparam int ADDR_STEP        = DATA_WIDTH/8;
    localparam int SLAVE_ADDR_SPAN  = SLAVE_REG_COUNT * ADDR_STEP;

    //------------------ address map -----------------------------
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE0_BASE = 8'hA0;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE1_BASE = 8'hC0;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE0_END  = SLAVE0_BASE + SLAVE_ADDR_SPAN - 1;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE1_END  = SLAVE1_BASE + SLAVE_ADDR_SPAN - 1;

    //------------------ response encodings ----------------------
    localparam logic [RESP_WIDTH-1:0]  RESP_OKAY   = 2'b00;
    localparam logic [RESP_WIDTH-1:0]  RESP_SLVERR = 2'b10;
    localparam logic [RESP_WIDTH-1:0]  RESP_DECERR = 2'b11;
    localparam logic [BURST_WIDTH-1:0] BURST_INCR  = 2'b01;

    //------------------ target select encodings -----------------
    localparam logic [SELECT_WIDTH-1:0] SEL_S0  = 2'd0;
    localparam logic [SELECT_WIDTH-1:0] SEL_S1  = 2'd1;
    localparam logic [SELECT_WIDTH-1:0] SEL_ERR = 2'd2;

endpackage
