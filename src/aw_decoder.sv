`timescale 1ns / 1ps
import param_pkg::*;

module aw_decoder(
    input  logic [ADDRESS_WIDTH-1:0] AWADDR_SKD,
    input  logic [LEN_WIDTH-1:0]     AWLEN_SKD,
    input  logic [BURST_WIDTH-1:0]   AWBURST_SKD,
 
    output logic [SELECT_WIDTH-1:0]  aw_sel
);
    //=================================================================
    // aw_last_addr is one bit wider than the address so an increment
    // past the top of the map is caught instead of wrapping.
    //=================================================================
    logic [ADDRESS_WIDTH:0]  aw_last_addr;

    always_comb begin
        aw_last_addr = {1'b0, AWADDR_SKD} + (AWLEN_SKD * ADDR_STEP);

        if (AWBURST_SKD != BURST_INCR)
            aw_sel = SEL_ERR;                                   // unsupported burst type
        else if (AWADDR_SKD[$clog2(ADDR_STEP)-1:0] != '0)
            aw_sel = SEL_ERR;                                   // unaligned start
        else if (AWADDR_SKD >= SLAVE0_BASE && AWADDR_SKD <= SLAVE0_END)
            aw_sel = (aw_last_addr <= {1'b0, SLAVE0_END}) ? SEL_S0 : SEL_ERR;
        else if (AWADDR_SKD >= SLAVE1_BASE && AWADDR_SKD <= SLAVE1_END)
            aw_sel = (aw_last_addr <= {1'b0, SLAVE1_END}) ? SEL_S1 : SEL_ERR;
        else
            aw_sel = SEL_ERR;                                   // start in no window
    end

endmodule
