`timescale 1ns / 1ps
import param_pkg::*;

// Single-slave (S1 only) address decoders. In-range INCR -> SEL_S1,
// everything else (wrong burst, unaligned, out-of-window, overflow) -> SEL_ERR.

module aw_decoder_1 (
    input  logic [ADDRESS_WIDTH-1:0] AWADDR_SKD,
    input  logic [LEN_WIDTH-1:0]     AWLEN_SKD,
    input  logic [BURST_WIDTH-1:0]   AWBURST_SKD,
    output logic [SELECT_WIDTH-1:0]  aw_sel
);
    logic [ADDRESS_WIDTH:0] aw_last_addr;
    always_comb begin
        aw_last_addr = {1'b0, AWADDR_SKD} + (AWLEN_SKD * ADDR_STEP);
        if (AWBURST_SKD != BURST_INCR)
            aw_sel = SEL_ERR;
        else if (AWADDR_SKD[$clog2(ADDR_STEP)-1:0] != '0)
            aw_sel = SEL_ERR;
        else if (AWADDR_SKD >= SLAVE1_BASE && AWADDR_SKD <= SLAVE1_END)
            aw_sel = (aw_last_addr <= {1'b0, SLAVE1_END}) ? SEL_S1 : SEL_ERR;
        else
            aw_sel = SEL_ERR;
    end
endmodule

module ar_decoder_1 (
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
        else if (ARADDR_SKD >= SLAVE1_BASE && ARADDR_SKD <= SLAVE1_END)
            ar_sel = (ar_last_addr <= {1'b0, SLAVE1_END}) ? SEL_S1 : SEL_ERR;
        else
            ar_sel = SEL_ERR;
    end
endmodule
