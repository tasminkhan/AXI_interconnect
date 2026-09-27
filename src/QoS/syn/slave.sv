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
    input  logic [QOS_WIDTH-1:0]       AWQOS_I,       // carried to b_qos_o
    input  logic                       AWVALID_I,
    output logic                       AWREADY_O,     // = ~awf_full

    //---------------- W channel (broadcast payload, demuxed valid) ---
    input  logic [DATA_WIDTH-1:0]      WDATA_I,
    input  logic [STROBE_WIDTH-1:0]    WSTRB_I,
    input  logic                       WLAST_I,
    input  logic                       WVALID_I,
    output logic                       WREADY_O,      // = (engine in W_BURST)

    //---------------- B channel (to response mux) --------------------
    output logic [ID_WIDTH-1:0]        BID_O,
    output logic [RESP_WIDTH-1:0]      BRESP_O,
    output logic [QOS_WIDTH-1:0]       b_qos_o,       // sideband, not AXI
    output logic                       BVALID_O,
    input  logic                       BREADY_I,

    //---------------- AR channel (from demux) ------------------------
    input  logic [ID_WIDTH-1:0]        ARID_I,
    input  logic [ADDRESS_WIDTH-1:0]   ARADDR_I,
    input  logic [LEN_WIDTH-1:0]       ARLEN_I,
    input  logic [QOS_WIDTH-1:0]       ARQOS_I,       // reorder key
    input  logic                       ARVALID_I,
    output logic                       ARREADY_O,     // = a pool slot is free

    //---------------- R channel (to read response mux) ---------------
    output logic [ID_WIDTH-1:0]        RID_O,
    output logic [DATA_WIDTH-1:0]      RDATA_O,
    output logic [RESP_WIDTH-1:0]      RRESP_O,
    output logic [QOS_WIDTH-1:0]       r_qos_o,       // sideband, not AXI
    output logic                       RLAST_O,
    output logic                       RVALID_O,
    input  logic                       RREADY_I,

    //---------------- W-ROUTING STATUS (to fabric) -------------------
    output logic [MASTER_TAG_WIDTH-1:0] w_owner_o,
    output logic                        w_owner_valid_o,
    output logic                        w_burst_end_o,

    //---------------- EXTERNAL REGISTER FILE INTERFACE ---------------
    // Register array lives outside this block; port promoted to top I/O
    // so the fabric area excludes the memory by construction.
    output logic                                 regs_we_o,
    output logic [($clog2(SLAVE_REG_COUNT))-1:0] regs_waddr_o,
    output logic [DATA_WIDTH-1:0]                regs_wdata_o,
    output logic [STROBE_WIDTH-1:0]              regs_wstrb_o,
    output logic [($clog2(SLAVE_REG_COUNT))-1:0] regs_raddr_o,
    input  logic [DATA_WIDTH-1:0]                regs_rdata_i
);

    //=================================================================
    // ENGINE STATE + REGISTERS  (declared before first use below)
    //=================================================================
    typedef enum logic [1:0] {W_IDLE, W_BURST, W_RESP} weng_state_t;
    weng_state_t weng_state;

    logic [ID_WIDTH-1:0]                      weng_id;
    logic [($clog2(SLAVE_REG_COUNT))-1:0]     weng_idx;
    logic [BEAT_COUNT_WIDTH-1:0]              weng_len;
    logic [BEAT_COUNT_WIDTH-1:0]              weng_beat;
    logic [QOS_WIDTH-1:0]                     weng_qos;   // -> b_qos_o

    typedef enum logic {R_IDLE, R_BURST} reng_state_t;
    reng_state_t reng_state;

    logic [ID_WIDTH-1:0]                  reng_id;
    logic [($clog2(SLAVE_REG_COUNT))-1:0] reng_idx;
    logic [BEAT_COUNT_WIDTH-1:0]          reng_len, reng_beat;
    logic [QOS_WIDTH-1:0]                 reng_qos;   // -> r_qos_o

    //-----------------------------------------------------------------
    // Register file : SLAVE_REG_COUNT x DATA_WIDTH, cleared on reset
    //-----------------------------------------------------------------
    wire regs_we = (weng_state == W_BURST) && WVALID_I && WREADY_O;

    assign regs_we_o    = regs_we;
    assign regs_waddr_o = weng_idx;
    assign regs_wdata_o = WDATA_I;
    assign regs_wstrb_o = WSTRB_I;
    assign regs_raddr_o = reng_idx;

    wire [DATA_WIDTH-1:0] rdata = regs_rdata_i;   // read data -> feeds RDATA_O

    //=================================================================
    // AW FIFO - STRICT ORDER, DO NOT REORDER (see header).
    //=================================================================
    logic [ID_WIDTH-1:0]        awf_id   [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0]   awf_addr [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]       awf_len  [0:SLAVE_FIFO_DEPTH-1];
    logic [QOS_WIDTH-1:0]       awf_qos  [0:SLAVE_FIFO_DEPTH-1];
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
            awf_qos [awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWQOS_I;
            awf_wp <= awf_wp + 1'b1;
        end
    end

    //=================================================================
    // WRITE ENGINE : W_IDLE -> W_BURST -> W_RESP   (unchanged logic)
    //=================================================================

    task automatic pop;
        weng_id    <= awf_id  [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_idx   <= awf_addr[awf_rp[SLAVE_PTR_WIDTH-2:0]][4:1];
        weng_len   <= awf_len [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_qos   <= awf_qos [awf_rp[SLAVE_PTR_WIDTH-2:0]];
        weng_beat  <= '0;
        awf_rp     <= awf_rp + 1'b1;
    endtask

    assign WREADY_O = (weng_state == W_BURST);

    assign w_owner_o       = weng_id[ID_WIDTH-1 -: MASTER_TAG_WIDTH];
    assign w_owner_valid_o = (weng_state == W_BURST);
    assign w_burst_end_o   = (weng_state == W_BURST) && WVALID_I && WREADY_O &&
                             ((weng_beat == weng_len) || WLAST_I);

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            weng_state <= W_IDLE;
            awf_rp     <= '0;
            BVALID_O   <= 1'b0;
            BID_O      <= '0;
            BRESP_O    <= RESP_OKAY;
            b_qos_o    <= '0;
            weng_id    <= '0;
            weng_idx   <= '0;
            weng_len   <= '0;
            weng_beat  <= '0;
            weng_qos   <= '0;
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
                        weng_idx  <= weng_idx + 1'b1;
                        weng_beat <= weng_beat + 1'b1;
                        if (weng_beat == weng_len) begin
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;
                            BRESP_O  <= WLAST_I ? RESP_OKAY : RESP_SLVERR;
                            b_qos_o  <= weng_qos;
                            weng_state <= W_RESP;
                        end else if (WLAST_I) begin       // WLAST early
                            BVALID_O <= 1'b1;
                            BID_O    <= weng_id;
                            BRESP_O  <= RESP_SLVERR;
                            b_qos_o  <= weng_qos;
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
    // READ SIDE : QoS reorder pool
    //=================================================================
    localparam int SLOT_W = $clog2(SLAVE_FIFO_DEPTH);

    logic [ID_WIDTH-1:0]      arf_id    [0:SLAVE_FIFO_DEPTH-1];
    logic [ADDRESS_WIDTH-1:0] arf_addr  [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]     arf_len   [0:SLAVE_FIFO_DEPTH-1];
    logic [QOS_WIDTH-1:0]     arf_qos   [0:SLAVE_FIFO_DEPTH-1];
    logic [AGE_WIDTH-1:0]     arf_age   [0:SLAVE_FIFO_DEPTH-1];
    logic                     arf_valid [0:SLAVE_FIFO_DEPTH-1];

    //-----------------------------------------------------------------
    // Free-slot finder : lowest-index invalid slot. ARREADY = one exists.
    //-----------------------------------------------------------------
    logic              free_avail;
    logic [SLOT_W-1:0] free_idx;

    always_comb begin
        free_avail = 1'b0;
        free_idx   = '0;
        for (int s = 0; s < SLAVE_FIFO_DEPTH; s++) begin
            if (!arf_valid[s] && !free_avail) begin
                free_avail = 1'b1;
                free_idx   = SLOT_W'(s);
            end
        end
    end
    assign ARREADY_O = free_avail;

    //-----------------------------------------------------------------
    // Picker : highest effective priority among valid slots. 
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
                    pick_idx   = SLOT_W'(s);
                    pick_eff   = eff[s];
                end
            end
        end
    end

    //-----------------------------------------------------------------
    // Read engine : R_IDLE -> R_BURST. 
    //-----------------------------------------------------------------

    assign RVALID_O = (reng_state == R_BURST);
    assign RID_O    = reng_id;
    assign RDATA_O  = rdata;
    assign RRESP_O  = RESP_OKAY;
    assign r_qos_o  = reng_qos;
    assign RLAST_O  = (reng_state == R_BURST) && (reng_beat == reng_len);

    wire reng_advancing =
        ( (reng_state == R_IDLE)  &&  pick_valid ) ||
        ( (reng_state == R_BURST) &&  RVALID_O && RREADY_I &&
          (reng_beat == reng_len) &&  pick_valid );

    //-----------------------------------------------------------------
    // arf_valid
    //-----------------------------------------------------------------
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            reng_state <= R_IDLE;
            reng_id    <= '0;
            reng_idx   <= '0;
            reng_len   <= '0;
            reng_beat  <= '0;
            reng_qos   <= '0;
            for (int j = 0; j < SLAVE_FIFO_DEPTH; j++) begin
                arf_valid[j] <= 1'b0;
                arf_age  [j] <= '0;
                arf_qos  [j] <= '0;
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

            //--------- AGE: valid, non-consumed slots tick up ----------
            for (int s = 0; s < SLAVE_FIFO_DEPTH; s++) begin
                if (arf_valid[s] && !(reng_advancing && (SLOT_W'(s) == pick_idx))) begin
                    if (arf_age[s] != {AGE_WIDTH{1'b1}})
                        arf_age[s] <= arf_age[s] + 1'b1;
                end
            end

            //--------- READ ENGINE -------------------------------------
            case (reng_state)
                R_IDLE: begin
                    if (pick_valid) begin
                        reng_id    <= arf_id  [pick_idx];
                        reng_idx   <= arf_addr[pick_idx][4:1];
                        reng_len   <= arf_len [pick_idx];
                        reng_qos   <= arf_qos [pick_idx];
                        reng_beat  <= '0;
                        arf_valid[pick_idx] <= 1'b0;
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
                                reng_qos   <= arf_qos [pick_idx];
                                reng_beat  <= '0;
                                arf_valid[pick_idx] <= 1'b0;
                            end else begin
                                reng_state <= R_IDLE;
                            end
                        end else begin
                            reng_idx  <= reng_idx  + 1'b1;
                            reng_beat <= reng_beat + 1'b1;
                        end
                    end
                end
                default: reng_state <= R_IDLE;
            endcase
        end
    end

endmodule
