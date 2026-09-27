`timescale 1ns / 1ps
import param_pkg::*;

// Read-address decoder - identical map/rules to aw_decoder.
module ar_decoder(
    input  logic [ADDRESS_WIDTH-1:0] ARADDR_SKD,
    input  logic [LEN_WIDTH-1:0]     ARLEN_SKD,
    input  logic [BURST_WIDTH-1:0]   ARBURST_SKD,
    output logic [SELECT_WIDTH-1:0]  ar_sel
);
    logic [ADDRESS_WIDTH:0] ar_last_addr;
    always_comb begin
        ar_last_addr = {1'b0, ARADDR_SKD} + (ARLEN_SKD * ADDR_STEP);
        if (ARBURST_SKD != BURST_INCR)
            ar_sel = SEL_ERR;
        else if (ARADDR_SKD[$clog2(ADDR_STEP)-1:0] != '0)
            ar_sel = SEL_ERR;
        else if (ARADDR_SKD >= SLAVE0_BASE && ARADDR_SKD <= SLAVE0_END)
            ar_sel = (ar_last_addr <= {1'b0, SLAVE0_END}) ? SEL_S0 : SEL_ERR;
        else if (ARADDR_SKD >= SLAVE1_BASE && ARADDR_SKD <= SLAVE1_END)
            ar_sel = (ar_last_addr <= {1'b0, SLAVE1_END}) ? SEL_S1 : SEL_ERR;
        else
            ar_sel = SEL_ERR;
    end
endmodule
