`timescale 1ns/1ps
//=====================================================================
// skidbuffer_dbg_tb.sv
// Watches the skid buffer's internal registers and flags via the debug
// ports, printing a per-cycle table. You control in_valid / out_ready
// each cycle in the stimulus loop and can see exactly how out_reg /
// tmp_reg / out_full / tmp_full respond.
//
// Build/run:
//   iverilog -g2012 -o sim skidbuffer_dbg_tb.sv skidbuffer_dbg.sv && vvp sim
//=====================================================================
module skidbuffer_tb;

    localparam int WIDTH = 8;

    logic             clk = 0, rst_n;
    logic [WIDTH-1:0] in_data;
    logic             in_valid, in_ready;
    logic [WIDTH-1:0] out_data;
    logic             out_valid, out_ready;

    // debug observation
    logic [WIDTH-1:0] dbg_out_reg, dbg_tmp_reg;
    logic             dbg_out_full, dbg_tmp_full, dbg_in_ready_early;

    skidbuffer #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .dbg_out_reg(dbg_out_reg), .dbg_tmp_reg(dbg_tmp_reg),
        .dbg_out_full(dbg_out_full), .dbg_tmp_full(dbg_tmp_full),
        .dbg_in_ready_early(dbg_in_ready_early)
    );

    always #5 clk = ~clk;

    // drive an incrementing payload; advance only on a real input handshake
    logic [WIDTH-1:0] seq = 5;
    assign in_data = seq;
    always @(posedge clk) if (rst_n && in_valid && in_ready) seq <= seq + 1;

    // ---- per-cycle observation table ----
    // Sampled just after each posedge (via a #1 in the loop) so the
    // register values shown are the post-edge state for that cycle.
    task show(input integer c);
        $display("%3d | inV=%b inR=%b | outV=%b outR=%b || out_full=%b tmp_full=%b | out_reg=%02h tmp_reg=%02h | in_data=%02h | rdy_early=%b",
                 c, in_valid, in_ready, out_valid, out_ready,
                 dbg_out_full, dbg_tmp_full, dbg_out_reg, dbg_tmp_reg,
                 in_data, dbg_in_ready_early);
    endtask

    integer i;
    initial begin
        $dumpfile("skid_dbg.vcd");
        $dumpvars(0, skidbuffer_tb);

        rst_n = 0; in_valid = 0; out_ready = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("cyc | inV   inR | outV outR || flags          | regs              | data  | early");
        $display("----+-----------+-----------++----------------+-------------------+-------+------");

        // A directed sequence you can read easily:
        //  - stream a few beats
        //  - stall downstream so tmp fills
        //  - resume
        for (i = 0; i < 24; i++) begin
            case (i)
                0,1,2:        begin in_valid<=1; out_ready<=1; end // stream
                3,4:          begin in_valid<=1; out_ready<=0; end // stall -> fill out then tmp
                5,6:          begin in_valid<=1; out_ready<=0; end // held full
                7:            begin in_valid<=1; out_ready<=1; end // drain one
                8:            begin in_valid<=1; out_ready<=0; end // stall again
                9,10:         begin in_valid<=1; out_ready<=1; end // drain
                default:      begin in_valid<=0; out_ready<=1; end // empty out
            endcase
            #1;             
            show(i);
            @(posedge clk);
        end

        $finish;
    end

    initial begin #5000; $display("TIMEOUT"); $finish; end

endmodule