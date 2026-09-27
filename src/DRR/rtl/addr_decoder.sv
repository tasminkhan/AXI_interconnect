`timescale 1ns / 1ps
import param_pkg::*;

module addr_decoder (
    input  logic [ADDRESS_WIDTH-1:0] ADDR_SKD,   // AWADDR_SKD  / ARADDR_SKD
    input  logic [LEN_WIDTH-1:0]     LEN_SKD,    // AWLEN_SKD   / ARLEN_SKD
    input  logic [BURST_WIDTH-1:0]   BURST_SKD,  // AWBURST_SKD / ARBURST_SKD

    output logic [SELECT_WIDTH-1:0]  sel         // aw_sel / ar_sel
);

    logic [ADDRESS_WIDTH:0] last_addr;   // start + (len * step), 1 bit wider
    logic [ADDRESS_WIDTH:0] base_ext;    // window base, same width
    logic [ADDRESS_WIDTH:0] end_ext;     // window last valid address
    logic                   aligned;
    logic                   hit;         // start address landed in a window

    always_comb begin
        last_addr = {1'b0, ADDR_SKD} + (LEN_SKD * ADDR_STEP);

        // beat alignment without a slice, so ADDR_STEP == 1 is also legal
        aligned   = ((ADDR_SKD & ADDRESS_WIDTH'(ADDR_STEP - 1)) == '0);

        sel       = SEL_ERR;             // default: no window claims it
        hit       = 1'b0;
        base_ext  = '0;
        end_ext   = '0;

        if ((BURST_SKD == BURST_INCR) && aligned) begin
            for (int s = 0; s < NUM_SLAVES; s++) begin
                base_ext = {1'b0, slave_base(s)};
                end_ext  = base_ext + SLAVE_ADDR_SPAN - 1;

                if (!hit && ({1'b0, ADDR_SKD} >= base_ext)
                         && ({1'b0, ADDR_SKD} <= end_ext)) begin
                    hit = 1'b1;
                    sel = (last_addr <= end_ext) ? SELECT_WIDTH'(s) : SEL_ERR;
                end
            end
        end
    end

endmodule
