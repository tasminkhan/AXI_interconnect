// The decoder in top guarantees every burst that reaches is legal
// (INCR, start and end inside the window), so the engine does not
// re-check range. Register index = (ADDR - BASE)/2; because both
// bases are 32-byte aligned this is now ADDR[4:1].

module slave #(
    parameter logic [7:0] BASE_ADDR = 8'hA0   // documentation / index comment
)(
    input  logic        ACLK,
    input  logic        ARESETn,

    //---------------- AW channel (from demux) ------------------------
    input  logic [3:0]  AWID_I,
    input  logic [7:0]  AWADDR_I,
    input  logic [3:0]  AWLEN_I,
    input  logic        AWVALID_I,     // this slave's demuxed valid
    output logic        AWREADY_O,     // = ~awf_full

    //---------------- W channel (broadcast payload, demuxed valid) ---
    input  logic [15:0] WDATA_I,
    input  logic [1:0]  WSTRB_I,
    input  logic        WLAST_I,
    input  logic        WVALID_I,
    output logic        WREADY_O,      // = (engine in W_BURST)

    //---------------- B channel (to response mux) --------------------
    output logic [3:0]  BID_O,
    output logic [1:0]  BRESP_O,
    output logic        BVALID_O,
    input  logic        BREADY_I
);

    `include "axi_params.svh"

    //-----------------------------------------------------------------
    // Register file : SLAVE_REG_COUNT x DATA_WIDTH, cleared on reset
    //-----------------------------------------------------------------
    logic [DATA_WIDTH-1:0] regs [0:SLAVE_REG_COUNT-1];

    //=================================================================
    // AW FIFO : depth SLAVE_FIFO_DEPTH, {id, addr, len} per entry.
    // Pointers carry a wrap bit (SLAVE_PTR_WIDTH = clog2(depth)+1).
    //=================================================================
    logic [ID_WIDTH-1:0]        awf_id   [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0]   awf_addr [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]       awf_len  [0:SLAVE_FIFO_DEPTH-1];
    logic [SLAVE_PTR_WIDTH-1:0] awf_wp, awf_rp;

    wire awf_empty = (awf_wp == awf_rp);
    wire awf_full  = (awf_wp[SLAVE_PTR_WIDTH-2:0] == awf_rp[SLAVE_PTR_WIDTH-2:0])
                   & (awf_wp[SLAVE_PTR_WIDTH-1]   != awf_rp[SLAVE_PTR_WIDTH-1]);

    assign AWREADY_O = ~awf_full;      // accept while there is queue space

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            awf_wp <= '0;
        end else if (AWVALID_I && AWREADY_O) begin   // AW handshake -> push
            awf_id  [awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWID_I;
            awf_addr[awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWADDR_I;
            awf_len [awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWLEN_I;
            awf_wp <= awf_wp + 1'b1;
        end
    end

    //=================================================================
    // WRITE ENGINE : W_IDLE -> W_BURST -> W_RESP
    //=================================================================
    typedef enum logic [1:0] {W_IDLE, W_BURST, W_RESP} weng_state_t;
    weng_state_t weng_state;

    logic [ID_WIDTH-1:0]        weng_id;    // popped AWID -> BID echo
    logic [REG_IDX_WIDTH-1:0]   weng_idx;   // current register index (steps +1/beat)
    logic [BEAT_COUNT_WIDTH-1:0] weng_len;  // popped AWLEN (beats-1)
    logic [BEAT_COUNT_WIDTH-1:0] weng_beat; // beat counter 0..len

    // Moore outputs: WREADY only in W_BURST.
    assign WREADY_O = (weng_state == W_BURST);

    integer i;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            weng_state <= W_IDLE;
            awf_rp     <= '0;
            BVALID_O   <= 1'b0;
            BID_O      <= '0;
            BRESP_O    <= RESP_OKAY;
            weng_id    <= '0;
            weng_idx   <= '0;
            weng_len   <= '0;
            weng_beat  <= '0;
            for (i = 0; i < SLAVE_REG_COUNT; i = i + 1)
                regs[i] <= '0;
        end else begin
            case (weng_state)
                //---------------------------------------------------
                // Pop the oldest queued address.
                //---------------------------------------------------
                W_IDLE: begin
                    if (!awf_empty) begin
                        weng_id   <= awf_id [awf_rp[SLAVE_PTR_WIDTH-2:0]];
                        // index = (ADDR - BASE)/ADDR_STEP; bases are
                        // 32-byte aligned so this is ADDR[4:1].
                        weng_idx  <= awf_addr[awf_rp[SLAVE_PTR_WIDTH-2:0]][4:1];
                        weng_len  <= awf_len[awf_rp[SLAVE_PTR_WIDTH-2:0]];
                        weng_beat <= '0;
                        awf_rp    <= awf_rp + 1'b1;
                        weng_state <= W_BURST;
                    end
                end
                //---------------------------------------------------
                // Per accepted beat: write strobed lanes, step index,
                // count. Last beat (beat==len / WLAST) -> response.
                //---------------------------------------------------
                W_BURST: begin
                    if (WVALID_I && WREADY_O) begin
                        if (WSTRB_I[0]) regs[weng_idx][7:0]  <= WDATA_I[7:0];
                        if (WSTRB_I[1]) regs[weng_idx][15:8] <= WDATA_I[15:8];
                        weng_idx  <= weng_idx + 1'b1;     // +ADDR_STEP bytes = next reg
                        weng_beat <= weng_beat + 1'b1;
                        if (weng_beat == weng_len) begin                
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;          // echo the transaction ID
                            BRESP_O  <= WLAST_I ? RESP_OKAY : RESP_SLVERR;
                            weng_state <= W_RESP;
                        end
                    end
                end
                
                //---------------------------------------------------
                // ONE response after the whole burst
                //---------------------------------------------------
                W_RESP: begin
                    if (BREADY_I) begin                   // BVALID_O & BREADY_I handshake
                        BVALID_O   <= 1'b0;
                        weng_state <= W_IDLE;             // pop next queued address
                    end
                end
                default: weng_state <= W_IDLE;
            endcase
        end
    end

endmodule
