package param_pkg;

    //------------------ fundamental (SET) -----------------------
    localparam int DATA_WIDTH    = 16;
    localparam int ADDRESS_WIDTH = 8;
    localparam int ID_WIDTH      = 6;
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
    localparam int AW_PAYLOAD_WIDTH = ID_WIDTH+ADDRESS_WIDTH+LEN_WIDTH+BURST_WIDTH+QOS_WIDTH;
    localparam int AR_PAYLOAD_WIDTH = AW_PAYLOAD_WIDTH;
    localparam int W_PAYLOAD_WIDTH  = DATA_WIDTH+STROBE_WIDTH+1;
    localparam int B_PAYLOAD_WIDTH  = ID_WIDTH+RESP_WIDTH;

    //------------------ capacity/structure (SET) ----------------
    localparam int WOUTSTANDING      = 8;
    localparam int NUM_SLAVES        = 3;
    localparam int NUM_MASTERS       = 3;
    localparam int SLAVE_FIFO_DEPTH  = 8;
    localparam int SELECT_FIFO_DEPTH = WOUTSTANDING;   
    localparam int SLAVE_REG_COUNT   = 16;

    //------------------ master tagging --------------------------
    localparam int MASTER_TAG_WIDTH = 2;                        // up to 4 masters
    localparam int ORIG_ID_WIDTH    = ID_WIDTH - MASTER_TAG_WIDTH;
    localparam int MASTER_IDX_WIDTH = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    //------------------ bandwidth weights (DRR) -----------------
    localparam int MASTER_WEIGHT [0:NUM_MASTERS-1] = '{ 6, 6, 6 };
    localparam int MASTER_WEIGHT_MAX = 6;      // must bound every entry above

    // Largest possible transaction cost, in beats. AXI LEN is beats-1.
    localparam int MAX_BURST_COST = (1 << LEN_WIDTH);          // 16

    localparam int QUANTUM_MIN  = MAX_BURST_COST;              // 16
    localparam int QUANTUM_STEP = MAX_BURST_COST;              // per weight unit

    localparam int MAX_QUANTUM   = QUANTUM_MIN + MASTER_WEIGHT_MAX*QUANTUM_STEP;
    localparam int DEFICIT_CAP   = 2*MAX_QUANTUM;
    localparam int DEFICIT_WIDTH = $clog2(DEFICIT_CAP + 1);
    localparam int COST_WIDTH    = LEN_WIDTH + 1;              // holds LEN+1

    function automatic int master_quantum(input int m);
        master_quantum = QUANTUM_MIN + MASTER_WEIGHT[m]*QUANTUM_STEP;
    endfunction
    
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
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE2_BASE = 8'hE0;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE0_END  = SLAVE0_BASE + SLAVE_ADDR_SPAN - 1;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE1_END  = SLAVE1_BASE + SLAVE_ADDR_SPAN - 1;
    localparam logic [ADDRESS_WIDTH-1:0] SLAVE2_END  = SLAVE2_BASE + SLAVE_ADDR_SPAN - 1;

    localparam logic [NUM_SLAVES*ADDRESS_WIDTH-1:0] SLAVE_BASE_FLAT =
        { SLAVE2_BASE, SLAVE1_BASE, SLAVE0_BASE };  // index 0 = low slice

    function automatic logic [ADDRESS_WIDTH-1:0] slave_base(input int i);
        case (i)
            0:       slave_base = SLAVE0_BASE;
            1:       slave_base = SLAVE1_BASE;
            2:       slave_base = SLAVE2_BASE;
            default: slave_base = SLAVE0_BASE;
        endcase
    endfunction

    //------------------ response encodings ----------------------
    localparam logic [RESP_WIDTH-1:0]  RESP_OKAY   = 2'b00;
    localparam logic [RESP_WIDTH-1:0]  RESP_SLVERR = 2'b10;
    localparam logic [RESP_WIDTH-1:0]  RESP_DECERR = 2'b11;
    localparam logic [BURST_WIDTH-1:0] BURST_INCR  = 2'b01;

    //------------------ target select encodings -----------------
    localparam logic [SELECT_WIDTH-1:0] SEL_S0  = 2'd0;
    localparam logic [SELECT_WIDTH-1:0] SEL_S1  = 2'd1;
    localparam logic [SELECT_WIDTH-1:0] SEL_S2  = 2'd2;
    localparam logic [SELECT_WIDTH-1:0] SEL_ERR = 2'd3;

endpackage

//=====================================================================
// param_assert 
//=====================================================================
`timescale 1ns / 1ps
import param_pkg::*;

module param_assert;

    generate
        if (MASTER_TAG_WIDTH < MASTER_IDX_WIDTH) begin : g_tag_vs_idx
            $error("MASTER_TAG_WIDTH must be >= MASTER_IDX_WIDTH for w_owner slicing");
        end
        if ((1 << MASTER_TAG_WIDTH) < NUM_MASTERS) begin : g_tag_narrow
            $error("MASTER_TAG_WIDTH too small to address NUM_MASTERS");
        end
        if ((MASTER_TAG_WIDTH + ORIG_ID_WIDTH) != ID_WIDTH) begin : g_id_split
            $error("MASTER_TAG_WIDTH + ORIG_ID_WIDTH must equal ID_WIDTH");
        end
        if (ORIG_ID_WIDTH < 1) begin : g_orig_zero
            $error("ORIG_ID_WIDTH must be at least 1");
        end
        if ((1 << SELECT_WIDTH) < NUM_TARGETS) begin : g_sel_narrow
            $error("SELECT_WIDTH too small to address NUM_TARGETS");
        end
        if (SELECT_FIFO_DEPTH < 1) begin : g_fifo_zero
            $error("SELECT_FIFO_DEPTH must be at least 1");
        end
        // THE DRR FLOOR. Without this a master whose burst costs more
        // than its quantum can never accumulate enough deficit to issue.
        if (QUANTUM_MIN < MAX_BURST_COST) begin : g_quantum_floor
            $error("QUANTUM_MIN must be >= MAX_BURST_COST or DRR livelocks");
        end
        if (DEFICIT_CAP < (MAX_QUANTUM + MAX_BURST_COST)) begin : g_cap_small
            $error("DEFICIT_CAP too small to hold one quantum plus a burst");
        end
    endgenerate

    initial begin
        if (MASTER_TAG_WIDTH < MASTER_IDX_WIDTH)
            $fatal(1, "MASTER_TAG_WIDTH=%0d < MASTER_IDX_WIDTH=%0d: w_owner slice breaks",
                      MASTER_TAG_WIDTH, MASTER_IDX_WIDTH);
        if ((1 << MASTER_TAG_WIDTH) < NUM_MASTERS)
            $fatal(1, "MASTER_TAG_WIDTH=%0d cannot address NUM_MASTERS=%0d",
                      MASTER_TAG_WIDTH, NUM_MASTERS);
        if ((MASTER_TAG_WIDTH + ORIG_ID_WIDTH) != ID_WIDTH)
            $fatal(1, "MASTER_TAG_WIDTH+ORIG_ID_WIDTH (%0d) != ID_WIDTH (%0d)",
                      MASTER_TAG_WIDTH + ORIG_ID_WIDTH, ID_WIDTH);
        if (ORIG_ID_WIDTH < 1)
            $fatal(1, "ORIG_ID_WIDTH must be >= 1");
        if ((1 << SELECT_WIDTH) < NUM_TARGETS)
            $fatal(1, "SELECT_WIDTH=%0d cannot address NUM_TARGETS=%0d",
                      SELECT_WIDTH, NUM_TARGETS);
        if (SELECT_FIFO_DEPTH < 1)
            $fatal(1, "SELECT_FIFO_DEPTH must be >= 1");
        if (QUANTUM_MIN < MAX_BURST_COST)
            $fatal(1, "QUANTUM_MIN=%0d < MAX_BURST_COST=%0d: DRR would livelock",
                      QUANTUM_MIN, MAX_BURST_COST);
        for (int m = 0; m < NUM_MASTERS; m++)
            if (MASTER_WEIGHT[m] > MASTER_WEIGHT_MAX)
                $fatal(1, "MASTER_WEIGHT[%0d]=%0d exceeds MASTER_WEIGHT_MAX=%0d",
                          m, MASTER_WEIGHT[m], MASTER_WEIGHT_MAX);
        if (DEFICIT_CAP < (MAX_QUANTUM + MAX_BURST_COST))
            $fatal(1, "DEFICIT_CAP=%0d too small (need >= %0d)",
                      DEFICIT_CAP, MAX_QUANTUM + MAX_BURST_COST);
    end

endmodule
