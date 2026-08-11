//------------------ fundamental (SET) -----------------------
localparam int DATA_WIDTH    = 16;
localparam int ADDRESS_WIDTH = 8;
localparam int ID_WIDTH      = 4;
localparam int LEN_WIDTH     = 4;   // max burst = 2^4 = 16 beats

//------------------ spec-fixed constants --------------------
localparam int RESP_WIDTH    = 2;   // OKAY=00 / SLVERR=10 / DECERR=11

//------------------ derived widths --------------------------
localparam int STROBE_WIDTH  = DATA_WIDTH/8;   // 2

//------------------ capacity/structure (SET) ----------------
localparam int SLAVE_FIFO_DEPTH = 4;    // per-slave AW address queue
localparam int SLAVE_REG_COUNT  = 16;   // registers per slave

//------------------ derived ---------------------------------
localparam int SLAVE_PTR_WIDTH  = $clog2(SLAVE_FIFO_DEPTH) + 1;  // 3 (wrap bit)
localparam int BEAT_COUNT_WIDTH = LEN_WIDTH;                     // 4
localparam int ADDR_STEP        = DATA_WIDTH/8;                  // 2 bytes per beat (AxSIZE omitted)
localparam int REG_IDX_WIDTH    = $clog2(SLAVE_REG_COUNT);       // 4

//------------------ response encodings ----------------------
localparam logic [RESP_WIDTH-1:0] RESP_OKAY   = 2'b00;
localparam logic [RESP_WIDTH-1:0] RESP_SLVERR = 2'b10;