// The read engine services the highest-ARQOS queued request next
// (tie-break: oldest / lowest slot index). Each burst still runs to its
// RLAST before the next is picked (AXI4-legal: no read-data interleaving).
//
// Port list is identical to slave.sv PLUS one input: ARQOS_I. So it is a
// drop-in on the same top instantiation, differing by that single wire.
//
// The write path (AW FIFO + write engine + register file) is copied
// VERBATIM from slave.sv - unchanged.

import param_pkg::*;

module slave_reorder #(
    parameter logic [ADDRESS_WIDTH-1:0] BASE_ADDR = SLAVE0_BASE
)(
    input  logic        ACLK,
    input  logic        ARESETn,

    //---------------- AW channel (from demux) ------------------------
    input  logic [ID_WIDTH-1:0]        AWID_I,
    input  logic [ADDRESS_WIDTH-1:0]   AWADDR_I,
    input  logic [LEN_WIDTH-1:0]       AWLEN_I,
    input  logic                       AWVALID_I,
    output logic                       AWREADY_O,

    //---------------- W channel (broadcast payload, demuxed valid) ---
    input  logic [DATA_WIDTH-1:0]      WDATA_I,
    input  logic [STROBE_WIDTH-1:0]    WSTRB_I,
    input  logic                       WLAST_I,
    input  logic                       WVALID_I,
    output logic                       WREADY_O,

    //---------------- B channel (to response mux) --------------------
    output logic [ID_WIDTH-1:0]        BID_O,
    output logic [RESP_WIDTH-1:0]      BRESP_O,
    output logic                       BVALID_O,
    input  logic                       BREADY_I,

    //---------------- AR channel (from demux) ------------------------
    input  logic [ID_WIDTH-1:0]        ARID_I,
    input  logic [ADDRESS_WIDTH-1:0]   ARADDR_I,
    input  logic [LEN_WIDTH-1:0]       ARLEN_I,
    input  logic [QOS_WIDTH-1:0]       ARQOS_I,    
    input  logic                       ARVALID_I,
    output logic                       ARREADY_O,

    //---------------- R channel (to read response mux) ---------------
    output logic [ID_WIDTH-1:0]        RID_O,
    output logic [DATA_WIDTH-1:0]      RDATA_O,
    output logic [RESP_WIDTH-1:0]      RRESP_O,
    output logic                       RLAST_O,
    output logic                       RVALID_O,
    input  logic                       RREADY_I,

    //---------------- DEBUG: one flat bus of all registers -----------
    output logic [SLAVE_REG_COUNT*DATA_WIDTH-1:0] dbg_regs
);
    //-----------------------------------------------------------------
    // Register file : SLAVE_REG_COUNT x DATA_WIDTH, cleared on reset
    //-----------------------------------------------------------------
    logic [DATA_WIDTH-1:0] regs [0:SLAVE_REG_COUNT-1];

    genvar g;
    generate
        for (g = 0; g < SLAVE_REG_COUNT; g++) begin : g_dbg
            assign dbg_regs[g*DATA_WIDTH +: DATA_WIDTH] = regs[g];
        end
    endgenerate

    //=================================================================
    //                       WRITE SIDE  : AW FIFO
    //=================================================================
    logic [ID_WIDTH-1:0]        awf_id   [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0]   awf_addr [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]       awf_len  [0:SLAVE_FIFO_DEPTH-1];
    logic [SLAVE_PTR_WIDTH-1:0] awf_wp, awf_rp;

    wire awf_empty = (awf_wp == awf_rp);
    wire awf_full  = (awf_wp[SLAVE_PTR_WIDTH-2:0] == awf_rp[SLAVE_PTR_WIDTH-2:0])
                   & (awf_wp[SLAVE_PTR_WIDTH-1]   != awf_rp[SLAVE_PTR_WIDTH-1]);

    assign AWREADY_O = ~awf_full;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            awf_wp <= '0;
        end else if (AWVALID_I && AWREADY_O) begin
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

    logic [ID_WIDTH-1:0]                      weng_id;
    logic [($clog2(SLAVE_REG_COUNT))-1:0]     weng_idx;
    logic [BEAT_COUNT_WIDTH-1:0]              weng_len;
    logic [BEAT_COUNT_WIDTH-1:0]              weng_beat;

    task automatic pop;
        weng_id    <= awf_id  [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_idx   <= awf_addr[awf_rp[SLAVE_PTR_WIDTH-2:0]][4:1];
        weng_len   <= awf_len [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_beat  <= '0;
        awf_rp     <= awf_rp + 1'b1;
    endtask

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
                W_IDLE: begin
                    if (!awf_empty) begin
                        pop();
                        weng_state <= W_BURST;
                    end
                end
                W_BURST: begin
                    if (WVALID_I && WREADY_O) begin
                        for (int b = 0; b < STROBE_WIDTH; b++)
                            if (WSTRB_I[b])
                                regs[weng_idx][b*8 +: 8] <= WDATA_I[b*8 +: 8];
                        weng_idx  <= weng_idx + 1'b1;
                        weng_beat <= weng_beat + 1'b1;
                        if (weng_beat == weng_len) begin
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;
                            BRESP_O  <= WLAST_I ? RESP_OKAY : RESP_SLVERR;
                            weng_state <= W_RESP;
                        end else if (WLAST_I) begin
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;
                            BRESP_O  <= RESP_SLVERR;
                            weng_state <= W_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (BREADY_I) begin
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
    // ================  READ SIDE : QoS reorder pool  ===============
    // AR queue as a valid-bit pool (random-access removal), one slot
    // per outstanding read. Stores {id, addr, len, qos}. 
    //=================================================================
    localparam int SLOT_W = $clog2(SLAVE_FIFO_DEPTH);

    logic [ID_WIDTH-1:0]      arf_id   [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0] arf_addr [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]     arf_len  [0:SLAVE_FIFO_DEPTH-1];
    logic [QOS_WIDTH-1:0]     arf_qos  [0:SLAVE_FIFO_DEPTH-1];
    logic                     arf_valid[0:SLAVE_FIFO_DEPTH-1];
    logic [AGE_WIDTH-1:0]     arf_age [0:SLAVE_FIFO_DEPTH-1];

    //-----------------------------------------------------------------
    // Free-slot finder : lowest-index invalid slot (for push).
    // ARREADY = a free slot exists.
    //-----------------------------------------------------------------
    logic                                free_avail;
    logic [$clog2(SLAVE_FIFO_DEPTH)-1:0] free_idx;
    
    always_comb begin
        free_avail = 1'b0;
        free_idx   = '0;
        for (int s = 0; s < SLAVE_FIFO_DEPTH; s++) begin
            if (!arf_valid[s] && !free_avail) begin
                free_avail = 1'b1;
                free_idx   = s[$clog2(SLAVE_FIFO_DEPTH)-1:0];
            end
        end
    end
    assign ARREADY_O = free_avail;

    //-----------------------------------------------------------------
    // QoS picker : among VALID slots, highest arf_qos wins; ties break
    // to the lowest slot index (oldest-first, since strict '>' never
    // displaces an equal-QoS earlier slot).
    //
    // ANTI-STARVATION HOOK: arf_qos[s] is compared with an effective priority  
    //-----------------------------------------------------------------
    logic [QOS_WIDTH-1:0] eff [0:SLAVE_FIFO_DEPTH-1];
    always_comb begin
        for (int s = 0; s < SLAVE_FIFO_DEPTH; s++)
            eff[s] = (arf_age[s] >= STARVE_LIMIT) ? QOS_MAX : arf_qos[s];
    end

    logic                 pick_valid;
    logic [SLOT_W-1:0]    pick_idx;
    logic [QOS_WIDTH-1:0] pick_eff;                 
    always_comb begin
        pick_valid = 1'b0;
        pick_idx   = '0;
        pick_eff   = '0;
        for (int s = 0; s < SLAVE_FIFO_DEPTH; s++) begin
            if (arf_valid[s]) begin
                if (!pick_valid || (eff[s] > pick_eff)) begin
                    pick_valid = 1'b1;
                    pick_idx   = s[SLOT_W-1:0];
                    pick_eff   = eff[s];
                end
            end
        end
    end
    
    //-----------------------------------------------------------------
    // Read engine : R_IDLE -> R_BURST. On entry (or back-to-back at the
    // last beat) it LOADS the picked slot and CLEARS its valid bit.
    //-----------------------------------------------------------------
    typedef enum logic {R_IDLE, R_BURST} reng_state_t;
    reng_state_t reng_state;

    logic [ID_WIDTH-1:0]                  reng_id;
    logic [($clog2(SLAVE_REG_COUNT))-1:0] reng_idx;
    logic [BEAT_COUNT_WIDTH-1:0]          reng_len, reng_beat;

    assign RVALID_O = (reng_state == R_BURST);
    assign RID_O    = reng_id;
    assign RDATA_O  = regs[reng_idx];
    assign RRESP_O  = RESP_OKAY;
    assign RLAST_O  = (reng_state == R_BURST) && (reng_beat == reng_len);
    
    wire reng_advancing =
        ( (reng_state == R_IDLE)  &&  pick_valid ) ||
        ( (reng_state == R_BURST) &&  RVALID_O && RREADY_I &&
          (reng_beat == reng_len) &&  pick_valid );

    // Push AND read-engine share arf_valid, so they live in ONE always_ff, 
    // Push targets free_idx(an INVALID slot); the engine clears pick_idx (a VALID slot); the
    // two indices can never coincide in a cycle, so there is no conflict.
    integer j;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            reng_state <= R_IDLE;
            reng_id    <= '0;
            reng_idx   <= '0;
            reng_len   <= '0;
            reng_beat  <= '0;
            for (j = 0; j < SLAVE_FIFO_DEPTH; j = j + 1) begin
                arf_valid[j] <= 1'b0;
                arf_age[j]   <= '0;
            end
        end else begin
            //--------- PUSH: accept AR into the lowest free slot -------
            if (ARVALID_I && ARREADY_O) begin
                arf_id   [free_idx] <= ARID_I;
                arf_addr [free_idx] <= ARADDR_I;
                arf_len  [free_idx] <= ARLEN_I;
                arf_qos  [free_idx] <= ARQOS_I;
                arf_valid[free_idx] <= 1'b1;
                arf_age  [free_idx] <= '0; 
            end
            
            //--------- AGE: valid, non-picked slots tick up ------------
            for (int s = 0; s < SLAVE_FIFO_DEPTH; s++) begin
                if (arf_valid[s]) begin
                    // not ageing the slot being consumed this cycle
                    if (!(reng_advancing && (s == pick_idx))) begin
                        if (arf_age[s] != {AGE_WIDTH{1'b1}})   
                            arf_age[s] <= arf_age[s] + 1'b1;
                    end
                end
            end

            //--------- READ ENGINE -------------------------------------
            case (reng_state)
                R_IDLE: begin
                    if (pick_valid) begin
                        reng_id    <= arf_id  [pick_idx];
                        reng_idx   <= arf_addr[pick_idx][4:1];
                        reng_len   <= arf_len [pick_idx];
                        reng_beat  <= '0;
                        arf_valid[pick_idx] <= 1'b0;   // clear on pick
                        reng_state <= R_BURST;
                    end
                end
                R_BURST: begin
                    if (RVALID_O && RREADY_I) begin        // beat accepted
                        if (reng_beat == reng_len) begin   // last beat done
                            if (pick_valid) begin          // back-to-back
                                reng_id    <= arf_id  [pick_idx];
                                reng_idx   <= arf_addr[pick_idx][4:1];
                                reng_len   <= arf_len [pick_idx];
                                reng_beat  <= '0;
                                arf_valid[pick_idx] <= 1'b0;
                                // stay in R_BURST
                            end else begin
                                reng_state <= R_IDLE;
                            end
                        end else begin
                            reng_idx  <= reng_idx  + 1'b1;
                            reng_beat <= reng_beat + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule