// Terminates every burst the decoder flagged as illegal:
//   * start address in no slave window,
//   * pre-calculated end address (start + AWLEN*ADDR_STEP) walking
//     past the target window, or
//   * unsupported burst type (anything but INCR).

// Per the AXI "no early burst termination" rule every beat is still
// transferred (WREADY high through the whole burst). Termination is
// COUNTER-authoritative (weng_beat == weng_len), so a missing WLAST
// can never hang it - matching the real slave.

module err_slave (
    input  logic        ACLK,
    input  logic        ARESETn,

    //---------------- AW channel (from demux, sel = SEL_ERR) ---------
    input  logic [3:0]  AWID_I,
    input  logic [3:0]  AWLEN_I,
    input  logic        AWVALID_I,
    output logic        AWREADY_O,

    //---------------- W channel --------------------------------------
    input  logic        WLAST_I,
    input  logic        WVALID_I,
    output logic        WREADY_O,

    //---------------- B channel (to response mux) --------------------
    output logic [3:0]  BID_O,
    output logic [1:0]  BRESP_O,
    output logic        BVALID_O,
    input  logic        BREADY_I
);

    `include "axi_params.svh"

    //=================================================================
    // AW FIFO : depth SLAVE_FIFO_DEPTH, {id, len} per entry.
    // (No addr stored - the error path never computes a register index.)
    //=================================================================
    logic [ID_WIDTH-1:0]        awf_id  [0:SLAVE_FIFO_DEPTH-1];
    logic [LEN_WIDTH-1:0]       awf_len [0:SLAVE_FIFO_DEPTH-1];
    logic [SLAVE_PTR_WIDTH-1:0] awf_wp, awf_rp;

    wire awf_empty = (awf_wp == awf_rp);
    wire awf_full  = (awf_wp[SLAVE_PTR_WIDTH-2:0] == awf_rp[SLAVE_PTR_WIDTH-2:0])
                   & (awf_wp[SLAVE_PTR_WIDTH-1]   != awf_rp[SLAVE_PTR_WIDTH-1]);

    assign AWREADY_O = ~awf_full;      // accept while there is queue space

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            awf_wp <= '0;
        end else if (AWVALID_I && AWREADY_O) begin   // AW handshake -> push
            awf_id [awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWID_I;
            awf_len[awf_wp[SLAVE_PTR_WIDTH-2:0]] <= AWLEN_I;
            awf_wp <= awf_wp + 1'b1;
        end
    end

    //=================================================================
    // ENGINE : EW_IDLE -> EW_BURST -> EW_RESP (no register writes)
    //=================================================================
    typedef enum logic [1:0] {EW_IDLE, EW_BURST, EW_RESP} estate_t;
    estate_t estate;

    logic [ID_WIDTH-1:0]         weng_id;
    logic [BEAT_COUNT_WIDTH-1:0] weng_len;
    logic [BEAT_COUNT_WIDTH-1:0] weng_beat;

    // Capture the AW directly from the ports (no FIFO). Latches id/len,
    // zeroes the beat counter. Caller sets the state.
    task automatic grab;
        weng_id   <= AWID_I;
        weng_len  <= AWLEN_I;
        weng_beat <= '0;
    endtask

    // AWREADY high only when we can take an address (IDLE, nothing in flight)
    assign AWREADY_O = (estate == EW_IDLE);
    assign WREADY_O  = (estate == EW_BURST);
    assign BVALID_O  = (estate == EW_RESP);
    assign BID_O     = weng_id;
    assign BRESP_O   = RESP_DECERR;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            estate <= EW_IDLE; weng_id <= '0; weng_len <= '0; weng_beat <= '0;
        end else case (estate)
            EW_IDLE:
                if (AWVALID_I && AWREADY_O) begin   // AW handshake -> capture
                    grab();
                    estate <= EW_BURST;
                end
            EW_BURST:
                if (WVALID_I && WREADY_O) begin
                    weng_beat <= weng_beat + 1'b1;
                    if (weng_beat == weng_len)      estate <= EW_RESP;
                    else if (WLAST_I)               estate <= EW_RESP;
                end
            EW_RESP:
                if (BREADY_I) estate <= EW_IDLE;    // response taken -> ready for next
            default: estate <= EW_IDLE;
        endcase
    end

endmodule


