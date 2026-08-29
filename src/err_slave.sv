// Terminates every burst the decoder flagged as illegal:
//   * start address in no slave window,
//   * pre-calculated end address (start + AWLEN*ADDR_STEP) walking
//     past the target window, or
//   * unsupported burst type (anything but INCR).

// Per the AXI "no early burst termination" rule every beat is still
// transferred (WREADY high through the whole burst). Termination is
// COUNTER-authoritative (weng_beat == weng_len), so a missing WLAST
// can never hang it - matching the real slave.
import param_pkg::*;

module err_slave (
    input  logic        ACLK,
    input  logic        ARESETn,

    //---------------- AW channel (from demux, sel = SEL_ERR) ---------
    input  logic [ID_WIDTH-1:0]      AWID_I,
    input  logic [LEN_WIDTH-1:0]     AWLEN_I,
    input  logic                     AWVALID_I,
    output logic                     AWREADY_O,

    //---------------- W channel --------------------------------------
    input  logic                     WLAST_I,
    input  logic                     WVALID_I,
    output logic                     WREADY_O,

    //---------------- B channel (to response mux) --------------------
    output logic [ID_WIDTH-1:0]      BID_O,
    output logic [RESP_WIDTH-1:0]    BRESP_O,
    output logic                     BVALID_O,
    input  logic                     BREADY_I,

    //---------------- AR channel (from demux, sel = SEL_ERR) ---------
    input  logic [ID_WIDTH-1:0]      ARID_I,
    input  logic [LEN_WIDTH-1:0]     ARLEN_I,
    input  logic                     ARVALID_I,
    output logic                     ARREADY_O,

    //---------------- R channel (to read response mux) ---------------
    output logic [ID_WIDTH-1:0]      RID_O,
    output logic [DATA_WIDTH-1:0]    RDATA_O,
    output logic [RESP_WIDTH-1:0]    RRESP_O,
    output logic                     RLAST_O,
    output logic                     RVALID_O,
    input  logic                     RREADY_I
);

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
    task automatic drain;
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
                    drain();
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
    
    //=================================================================
    // READ ERROR ENGINE : ER_IDLE -> ER_BURST
    // A read that misses the map must still return ARLEN+1 data beats
    // (no early termination); each beat carries RRESP = DECERR and
    // RDATA = 0, with RLAST on the final beat.
    //=================================================================
    typedef enum logic {ER_IDLE, ER_BURST} rstate_t;
    rstate_t rstate;

    logic [ID_WIDTH-1:0]         reng_id;
    logic [BEAT_COUNT_WIDTH-1:0] reng_len, reng_beat;

    task automatic rgrab;
        reng_id   <= ARID_I;
        reng_len  <= ARLEN_I;
        reng_beat <= '0;
    endtask

    assign ARREADY_O = (rstate == ER_IDLE);
    assign RVALID_O  = (rstate == ER_BURST);
    assign RID_O     = reng_id;
    assign RDATA_O   = '0;
    assign RRESP_O   = RESP_DECERR;
    assign RLAST_O   = (rstate == ER_BURST) && (reng_beat == reng_len);

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rstate <= ER_IDLE; reng_id <= '0; reng_len <= '0; reng_beat <= '0;
        end else case (rstate)
            ER_IDLE:
                if (ARVALID_I && ARREADY_O) begin
                    rgrab();
                    rstate <= ER_BURST;
                end
            ER_BURST:
                if (RVALID_O && RREADY_I) begin
                    if (reng_beat == reng_len) rstate <= ER_IDLE;
                    else                       reng_beat <= reng_beat + 1'b1;
                end
        endcase
    end

endmodule


