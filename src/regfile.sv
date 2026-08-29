import param_pkg::*;

// Plain synchronous-write / combinational-read register file, factored
// out so synthesis reports it as its own instance (separate from the
// read/write engine logic around it).
module regfile (
    input  logic ACLK,
    input  logic ARESETn,

    input  logic                                   we,
    input  logic [($clog2(SLAVE_REG_COUNT))-1:0]   waddr,
    input  logic [DATA_WIDTH-1:0]                  wdata,
    input  logic [STROBE_WIDTH-1:0]                wstrb,

    input  logic [($clog2(SLAVE_REG_COUNT))-1:0]   raddr,
    output logic [DATA_WIDTH-1:0]                  rdata,

    output logic [SLAVE_REG_COUNT*DATA_WIDTH-1:0]  dbg_regs
);
    logic [DATA_WIDTH-1:0] regs [0:SLAVE_REG_COUNT-1];

    assign rdata = regs[raddr];

    genvar g;
    generate
        for (g = 0; g < SLAVE_REG_COUNT; g++) begin : g_dbg
            assign dbg_regs[g*DATA_WIDTH +: DATA_WIDTH] = regs[g];
        end
    endgenerate

    integer i;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            for (i = 0; i < SLAVE_REG_COUNT; i = i + 1)
                regs[i] <= '0;
        end else if (we) begin
            for (int b = 0; b < STROBE_WIDTH; b++)
                if (wstrb[b])
                    regs[waddr][b*8 +: 8] <= wdata[b*8 +: 8];
        end
    end
endmodule
