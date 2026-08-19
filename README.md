# AXI-interconnect

A synthesizable AXI4 **write-path** interconnect in SystemVerilog: one master
port, two register slaves, and a decode-error responder.

This repo tracks ongoing work — the read path (AR/R) and multi-master support
are planned.

## What's implemented

- **Master port** — three depth-2 skid buffers (AW/W forward, B return) that
  register the channel boundary for timing closure.
- **Fabric** (`top_interconnect`)
  - `aw_decoder` — combinational address decode + burst pre-check
    (INCR-only, alignment, window-overflow) → target select.
  - **Select FIFO** — remembers each outstanding write's target and length so
    the address-less W channel can be steered in AW order; counter-authoritative
    burst termination (never hangs on a missing/mismatched WLAST).
  - **AW/W demux** — payload broadcast, VALID/READY steered per target.
  - `b_arbiter` — round-robin B-response mux; responses route by BID and may
    return **out of order** across slaves.
- **Slaves** (`slave`) — 16-register file, AW FIFO (multi-outstanding),
  write engine with WSTRB byte-lane writes and WLAST/length cross-check
  (mismatch → SLVERR).
- **Error responder** (`err_slave`) — drains illegal bursts and returns DECERR
  (single-outstanding).

All widths, the address map, and capacities come from `param_pkg.sv`.

## Structure

- `src/` — SystemVerilog source (`.sv`) and per-block testbenches (`*_tb.sv`)
- `doc/` — design notes
