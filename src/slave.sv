// The decoder in top guarantees every burst that reaches is legal
// (INCR, start and end inside the window), so the engine does not
// re-check range. Register index = (ADDR - BASE)/2; because both
// bases are 32-byte aligned this is now ADDR[4:1].
import param_pkg::*;

module slave #(
    parameter logic [ADDRESS_WIDTH-1:0] BASE_ADDR = SLAVE0_BASE
)(
    input  logic        ACLK,
    input  logic        ARESETn,

    //---------------- AW channel (from demux) ------------------------
    input  logic [ID_WIDTH-1:0]        AWID_I,
    input  logic [ADDRESS_WIDTH-1:0]   AWADDR_I,
    input  logic [LEN_WIDTH-1:0]       AWLEN_I,
    input  logic                       AWVALID_I,     // this slave's demuxed valid
    output logic                       AWREADY_O,     // = ~awf_full

    //---------------- W channel (broadcast payload, demuxed valid) ---
    input  logic [DATA_WIDTH-1:0]      WDATA_I,
    input  logic [STROBE_WIDTH-1:0]    WSTRB_I,
    input  logic                       WLAST_I,
    input  logic                       WVALID_I,
    output logic                       WREADY_O,     // = (engine in W_BURST)

    //---------------- B channel (to response mux) --------------------
    output logic [ID_WIDTH-1:0]        BID_O,
    output logic [RESP_WIDTH-1:0]      BRESP_O,
    output logic                       BVALID_O,
    input  logic                       BREADY_I,
    
    //---------------- AR channel (from demux) ------------------------
    input  logic [ID_WIDTH-1:0]        ARID_I,
    input  logic [ADDRESS_WIDTH-1:0]   ARADDR_I,
    input  logic [LEN_WIDTH-1:0]       ARLEN_I,
    input  logic                       ARVALID_I,
    output logic                       ARREADY_O,

    //---------------- R channel (to read response mux) ---------------
    output logic [ID_WIDTH-1:0]        RID_O,
    output logic [DATA_WIDTH-1:0]      RDATA_O,
    output logic [RESP_WIDTH-1:0]      RRESP_O,
    output logic                       RLAST_O,
    output logic                       RVALID_O,
    input  logic                       RREADY_I,
    
    //---------------- DEBUG: one port per register ----
    output logic [SLAVE_REG_COUNT*DATA_WIDTH-1:0] dbg_regs
);
    //-----------------------------------------------------------------
    // Register file : SLAVE_REG_COUNT x DATA_WIDTH, cleared on reset
    //-----------------------------------------------------------------
    wire regs_we = (weng_state == W_BURST) && WVALID_I && WREADY_O;

    logic [DATA_WIDTH-1:0] rdata;   // read port -> feeds RDATA_O

    regfile u_regs (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .we    (regs_we),
        .waddr (weng_idx),
        .wdata (WDATA_I),
        .wstrb (WSTRB_I),
        .raddr (reng_idx),
        .rdata (rdata),
        .dbg_regs (dbg_regs)
    );

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

    logic [ID_WIDTH-1:0]                      weng_id;    // popped AWID -> BID echo
    logic [($clog2(SLAVE_REG_COUNT))-1:0]     weng_idx;   // current register index (steps +1/beat)
    logic [BEAT_COUNT_WIDTH-1:0]              weng_len;  // popped AWLEN (beats-1)
    logic [BEAT_COUNT_WIDTH-1:0]              weng_beat; // beat counter 0..len

    //task to pop addresses 
    task automatic pop;
        weng_id    <= awf_id  [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_idx   <= awf_addr[awf_rp[SLAVE_PTR_WIDTH-2:0]][4:1];
        weng_len   <= awf_len [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_beat  <= '0;
        awf_rp     <= awf_rp + 1'b1;
    endtask
    
    // Moore outputs: WREADY only in W_BURST.
    assign WREADY_O = (weng_state == W_BURST);

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
        end else begin
            case (weng_state)
                //---------------------------------------------------
                // Pop the oldest queued address.
                //---------------------------------------------------
                W_IDLE: begin
                    if (!awf_empty) begin
                        pop();
                        weng_state <= W_BURST;
                    end
                end
                //---------------------------------------------------
                // Per accepted beat: write strobed lanes, step index,
                // count. Last beat (beat==len / WLAST) -> response.
                //---------------------------------------------------
                W_BURST: begin
                    if (WVALID_I && WREADY_O) begin
                        weng_idx  <= weng_idx + 1'b1;     // +ADDR_STEP bytes = next reg
                        weng_beat <= weng_beat + 1'b1;
                        if (weng_beat == weng_len) begin                
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;          // echo the transaction ID
                            BRESP_O  <= WLAST_I ? RESP_OKAY : RESP_SLVERR;
                            weng_state <= W_RESP;
                        end else if (WLAST_I) begin       // WLAST early -> short burst
                            // Master asserted LAST before the final beat.
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;
                            BRESP_O  <= RESP_SLVERR;
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
                        if (!awf_empty) begin
                            pop();
                            weng_state <= W_BURST;
                        end else
                            weng_state <= W_IDLE;             
                    end
                end
                default: weng_state <= W_IDLE;
            endcase
        end
    end

    //=================================================================
    // AR FIFO : depth SLAVE_FIFO_DEPTH, {id, addr, len} per entry.
    // Symmetric to the AW FIFO. Multi-outstanding reads.
    //=================================================================
    logic [ID_WIDTH-1:0]        arf_id   [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0]   arf_addr [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]       arf_len  [0:SLAVE_FIFO_DEPTH-1];
    logic [SLAVE_PTR_WIDTH-1:0] arf_wp, arf_rp;

    wire arf_empty = (arf_wp == arf_rp);
    wire arf_full  = (arf_wp[SLAVE_PTR_WIDTH-2:0] == arf_rp[SLAVE_PTR_WIDTH-2:0])
                   & (arf_wp[SLAVE_PTR_WIDTH-1]   != arf_rp[SLAVE_PTR_WIDTH-1]);

    assign ARREADY_O = ~arf_full;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            arf_wp <= '0;
        end else if (ARVALID_I && ARREADY_O) begin
            arf_id  [arf_wp[SLAVE_PTR_WIDTH-2:0]] <= ARID_I;
            arf_addr[arf_wp[SLAVE_PTR_WIDTH-2:0]] <= ARADDR_I;
            arf_len [arf_wp[SLAVE_PTR_WIDTH-2:0]] <= ARLEN_I;
            arf_wp <= arf_wp + 1'b1;
        end
    end
    
    //=================================================================
    // READ ENGINE : R_IDLE -> R_BURST. RDATA comes from the same
    // register file the writes target, so a read reflects prior writes.
    // Counter-authoritative: emits ARLEN+1 beats, RLAST on the last.
    //=================================================================
    typedef enum logic {R_IDLE, R_BURST} reng_state_t;
    reng_state_t reng_state;

    logic [ID_WIDTH-1:0]                  reng_id;
    logic [($clog2(SLAVE_REG_COUNT))-1:0] reng_idx;
    logic [BEAT_COUNT_WIDTH-1:0]          reng_len, reng_beat;

    task automatic rpop;
        reng_id   <= arf_id  [arf_rp[SLAVE_PTR_WIDTH-2:0]];
        reng_idx  <= arf_addr[arf_rp[SLAVE_PTR_WIDTH-2:0]][4:1];
        reng_len  <= arf_len [arf_rp[SLAVE_PTR_WIDTH-2:0]];
        reng_beat <= '0;
        arf_rp    <= arf_rp + 1'b1;
    endtask

    // outputs driven from state + current index.
    assign RVALID_O = (reng_state == R_BURST);
    assign RID_O    = reng_id;
    assign RDATA_O = rdata;    assign RRESP_O  = RESP_OKAY;
    assign RLAST_O  = (reng_state == R_BURST) && (reng_beat == reng_len);

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            reng_state <= R_IDLE;
            arf_rp     <= '0;
            reng_id    <= '0;
            reng_idx   <= '0;
            reng_len   <= '0;
            reng_beat  <= '0;
        end else case (reng_state)
            R_IDLE:
                if (!arf_empty) begin
                    rpop();
                    reng_state <= R_BURST;
                end
            R_BURST:
                if (RVALID_O && RREADY_I) begin       // beat accepted
                    if (reng_beat == reng_len) begin  // last beat done
                        if (!arf_empty) rpop();       // back-to-back
                            else reng_state <= R_IDLE;
                    end else begin
                        reng_idx  <= reng_idx + 1'b1;
                        reng_beat <= reng_beat + 1'b1;
                    end
                end
        endcase
    end
    
endmodule
