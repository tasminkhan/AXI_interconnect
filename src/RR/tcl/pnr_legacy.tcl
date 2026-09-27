##############################################################################
#  pnr_neuron_asap7_1x_legacy.tcl
#  ASAP7 1x  --  LEGACY Innovus UI.  Follows the official ASAP7
#  example_innovus.tcl. Only necessary changes made:
#    - design paths / top cell / mmmc for this design
#    - pin placement uses YOUR side arrangement
#    - dimensions use the 1x tech pitches; row_h = 0.270 (from SITE)
#
#  Launch (NO -stylus):
#    cd /projects/CM_BTAP/work/btapuser50ddc/axi/RR/pnr
#    innovus -init tcl/pnr_legacy.tcl
##############################################################################

set pdk /projects/CM_BTAP/work/btapuser50ddc/pdks/asap7/asap7sc7p5t_28
set syn /projects/CM_BTAP/work/btapuser50ddc/axi/RR/syn/outputs

# --- design init (replaces the example's <your_global_init_files>.globals) ---
setDesignMode -process 7

set init_lef_file [list \
    $pdk/techlef_misc/asap7_tech_1x_201209.lef \
    $pdk/LEF/asap7sc7p5t_28_R_1x_220121a.lef ]
set init_verilog   $syn/top_asap7_ccs_netlist.v
set init_top_cell  top
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file tcl/mmmc_legacy.tcl

init_design

# this is example tcl to make a flexible floorplan size (1x core density flow)

# landscape 2:1 (width = 2 x height)  ->  aspect ratio (H/W) = 0.5
floorPlan -coreMarginsBy die -site asap7sc7p5t \
          -r 0.6 0.50 1.2 1.4 1.2 1.4

# Innovus is not putting tracks on the bottom cell row. That causes problems
# since it won't route to them on proper tracks.
# This moves the core up one.
# changeFloorplan -coreToBottom 1.08

add_tracks -honor_pitch

##############################################################################
# PIN PLACEMENT  (RR AXI crossbar, names verified from Genus get_ports)
#   LEFT   : ACLK, ARESETn
#   TOP    : master 0 AXI ports, then slave 0 regfile ports
#   BOTTOM : master 1 AXI ports, then slave 1 regfile ports
#   (ports in natural channel order, NOT grouped by read/write)
##############################################################################
set pins_left {\
    {AWID[1][1]} {AWID[1][0]} {AWADDR[1][7]} {AWADDR[1][6]} {AWADDR[1][5]} {AWADDR[1][4]} {AWADDR[1][3]} {AWADDR[1][2]} \
    {AWADDR[1][1]} {AWADDR[1][0]} {AWLEN[1][3]} {AWLEN[1][2]} {AWLEN[1][1]} {AWLEN[1][0]} {AWBURST[1][1]} {AWBURST[1][0]} \
    {AWQOS[1][3]} {AWQOS[1][2]} {AWQOS[1][1]} {AWQOS[1][0]} {AWVALID[1]} {AWREADY[1]} {WDATA[1][15]} {WDATA[1][14]} \
    {WDATA[1][13]} {WDATA[1][12]} {WDATA[1][11]} {WDATA[1][10]} {WDATA[1][9]} {WDATA[1][8]} {WDATA[1][7]} {WDATA[1][6]} \
    {WDATA[1][5]} {WDATA[1][4]} {WDATA[1][3]} {WDATA[1][2]} {WDATA[1][1]} {WDATA[1][0]} {WSTRB[1][1]} {WSTRB[1][0]} \
    {WLAST[1]} {WVALID[1]} {WREADY[1]} {BID[1][1]} {BID[1][0]} {BRESP[1][1]} {BRESP[1][0]} {BVALID[1]} \
    {BREADY[1]} {ARID[1][1]} {ARID[1][0]} {ARADDR[1][7]} {ARADDR[1][6]} {ARADDR[1][5]} {ARADDR[1][4]} {ARADDR[1][3]} \
    {ARADDR[1][2]} {ARADDR[1][1]} {ARADDR[1][0]} {ARLEN[1][3]} {ARLEN[1][2]} {ARLEN[1][1]} {ARLEN[1][0]} {ARBURST[1][1]} \
    {ARBURST[1][0]} {ARQOS[1][3]} {ARQOS[1][2]} {ARQOS[1][1]} {ARQOS[1][0]} {ARVALID[1]} {ARREADY[1]} {RID[1][1]} \
    {RID[1][0]} {RDATA[1][15]} {RDATA[1][14]} {RDATA[1][13]} {RDATA[1][12]} {RDATA[1][11]} {RDATA[1][10]} {RDATA[1][9]} \
    {RDATA[1][8]} {RDATA[1][7]} {RDATA[1][6]} {RDATA[1][5]} {RDATA[1][4]} {RDATA[1][3]} {RDATA[1][2]} {RDATA[1][1]} \
    {RDATA[1][0]} {RRESP[1][1]} {RRESP[1][0]} {RLAST[1]} {RVALID[1]} {RREADY[1]} \
}

set pins_right {\
    ACLK ARESETn {REGS_WE[1]} {REGS_WADDR[1][3]} {REGS_WADDR[1][2]} {REGS_WADDR[1][1]} {REGS_WADDR[1][0]} {REGS_WDATA[1][15]} \
    {REGS_WDATA[1][14]} {REGS_WDATA[1][13]} {REGS_WDATA[1][12]} {REGS_WDATA[1][11]} {REGS_WDATA[1][10]} {REGS_WDATA[1][9]} {REGS_WDATA[1][8]} {REGS_WDATA[1][7]} \
    {REGS_WDATA[1][6]} {REGS_WDATA[1][5]} {REGS_WDATA[1][4]} {REGS_WDATA[1][3]} {REGS_WDATA[1][2]} {REGS_WDATA[1][1]} {REGS_WDATA[1][0]} {REGS_WSTRB[1][1]} \
    {REGS_WSTRB[1][0]} {REGS_RADDR[1][3]} {REGS_RADDR[1][2]} {REGS_RADDR[1][1]} {REGS_RADDR[1][0]} {REGS_RDATA[1][15]} {REGS_RDATA[1][14]} {REGS_RDATA[1][13]} \
    {REGS_RDATA[1][12]} {REGS_RDATA[1][11]} {REGS_RDATA[1][10]} {REGS_RDATA[1][9]} {REGS_RDATA[1][8]} {REGS_RDATA[1][7]} {REGS_RDATA[1][6]} {REGS_RDATA[1][5]} \
    {REGS_RDATA[1][4]} {REGS_RDATA[1][3]} {REGS_RDATA[1][2]} {REGS_RDATA[1][1]} {REGS_RDATA[1][0]} \
}

set pins_top {\
    {AWID[0][1]} {AWID[0][0]} {AWADDR[0][7]} {AWADDR[0][6]} {AWADDR[0][5]} {AWADDR[0][4]} {AWADDR[0][3]} {AWADDR[0][2]} \
    {AWADDR[0][1]} {AWADDR[0][0]} {AWLEN[0][3]} {AWLEN[0][2]} {AWLEN[0][1]} {AWLEN[0][0]} {AWBURST[0][1]} {AWBURST[0][0]} \
    {AWQOS[0][3]} {AWQOS[0][2]} {AWQOS[0][1]} {AWQOS[0][0]} {AWVALID[0]} {AWREADY[0]} {WDATA[0][15]} {WDATA[0][14]} \
    {WDATA[0][13]} {WDATA[0][12]} {WDATA[0][11]} {WDATA[0][10]} {WDATA[0][9]} {WDATA[0][8]} {WDATA[0][7]} {WDATA[0][6]} \
    {WDATA[0][5]} {WDATA[0][4]} {WDATA[0][3]} {WDATA[0][2]} {WDATA[0][1]} {WDATA[0][0]} {WSTRB[0][1]} {WSTRB[0][0]} \
    {WLAST[0]} {WVALID[0]} {WREADY[0]} {BID[0][1]} {BID[0][0]} {BRESP[0][1]} {BRESP[0][0]} {BVALID[0]} \
    {BREADY[0]} {ARID[0][1]} {ARID[0][0]} {ARADDR[0][7]} {ARADDR[0][6]} {ARADDR[0][5]} {ARADDR[0][4]} {ARADDR[0][3]} \
    {ARADDR[0][2]} {ARADDR[0][1]} {ARADDR[0][0]} {ARLEN[0][3]} {ARLEN[0][2]} {ARLEN[0][1]} {ARLEN[0][0]} {ARBURST[0][1]} \
    {ARBURST[0][0]} {ARQOS[0][3]} {ARQOS[0][2]} {ARQOS[0][1]} {ARQOS[0][0]} {ARVALID[0]} {ARREADY[0]} {RID[0][1]} \
    {RID[0][0]} {RDATA[0][15]} {RDATA[0][14]} {RDATA[0][13]} {RDATA[0][12]} {RDATA[0][11]} {RDATA[0][10]} {RDATA[0][9]} \
    {RDATA[0][8]} {RDATA[0][7]} {RDATA[0][6]} {RDATA[0][5]} {RDATA[0][4]} {RDATA[0][3]} {RDATA[0][2]} {RDATA[0][1]} \
    {RDATA[0][0]} {RRESP[0][1]} {RRESP[0][0]} {RLAST[0]} {RVALID[0]} {RREADY[0]} {REGS_WE[0]} {REGS_WADDR[0][3]} \
    {REGS_WADDR[0][2]} {REGS_WADDR[0][1]} {REGS_WADDR[0][0]} {REGS_WDATA[0][15]} {REGS_WDATA[0][14]} {REGS_WDATA[0][13]} {REGS_WDATA[0][12]} {REGS_WDATA[0][11]} \
    {REGS_WDATA[0][10]} {REGS_WDATA[0][9]} {REGS_WDATA[0][8]} {REGS_WDATA[0][7]} {REGS_WDATA[0][6]} {REGS_WDATA[0][5]} {REGS_WDATA[0][4]} {REGS_WDATA[0][3]} \
    {REGS_WDATA[0][2]} {REGS_WDATA[0][1]} {REGS_WDATA[0][0]} {REGS_WSTRB[0][1]} {REGS_WSTRB[0][0]} {REGS_RADDR[0][3]} {REGS_RADDR[0][2]} {REGS_RADDR[0][1]} \
    {REGS_RADDR[0][0]} {REGS_RDATA[0][15]} {REGS_RDATA[0][14]} {REGS_RDATA[0][13]} {REGS_RDATA[0][12]} {REGS_RDATA[0][11]} {REGS_RDATA[0][10]} {REGS_RDATA[0][9]} \
    {REGS_RDATA[0][8]} {REGS_RDATA[0][7]} {REGS_RDATA[0][6]} {REGS_RDATA[0][5]} {REGS_RDATA[0][4]} {REGS_RDATA[0][3]} {REGS_RDATA[0][2]} {REGS_RDATA[0][1]} \
    {REGS_RDATA[0][0]} \
}

set pins_bottom {\
    {AWID[2][1]} {AWID[2][0]} {AWADDR[2][7]} {AWADDR[2][6]} {AWADDR[2][5]} {AWADDR[2][4]} {AWADDR[2][3]} {AWADDR[2][2]} \
    {AWADDR[2][1]} {AWADDR[2][0]} {AWLEN[2][3]} {AWLEN[2][2]} {AWLEN[2][1]} {AWLEN[2][0]} {AWBURST[2][1]} {AWBURST[2][0]} \
    {AWQOS[2][3]} {AWQOS[2][2]} {AWQOS[2][1]} {AWQOS[2][0]} {AWVALID[2]} {AWREADY[2]} {WDATA[2][15]} {WDATA[2][14]} \
    {WDATA[2][13]} {WDATA[2][12]} {WDATA[2][11]} {WDATA[2][10]} {WDATA[2][9]} {WDATA[2][8]} {WDATA[2][7]} {WDATA[2][6]} \
    {WDATA[2][5]} {WDATA[2][4]} {WDATA[2][3]} {WDATA[2][2]} {WDATA[2][1]} {WDATA[2][0]} {WSTRB[2][1]} {WSTRB[2][0]} \
    {WLAST[2]} {WVALID[2]} {WREADY[2]} {BID[2][1]} {BID[2][0]} {BRESP[2][1]} {BRESP[2][0]} {BVALID[2]} \
    {BREADY[2]} {ARID[2][1]} {ARID[2][0]} {ARADDR[2][7]} {ARADDR[2][6]} {ARADDR[2][5]} {ARADDR[2][4]} {ARADDR[2][3]} \
    {ARADDR[2][2]} {ARADDR[2][1]} {ARADDR[2][0]} {ARLEN[2][3]} {ARLEN[2][2]} {ARLEN[2][1]} {ARLEN[2][0]} {ARBURST[2][1]} \
    {ARBURST[2][0]} {ARQOS[2][3]} {ARQOS[2][2]} {ARQOS[2][1]} {ARQOS[2][0]} {ARVALID[2]} {ARREADY[2]} {RID[2][1]} \
    {RID[2][0]} {RDATA[2][15]} {RDATA[2][14]} {RDATA[2][13]} {RDATA[2][12]} {RDATA[2][11]} {RDATA[2][10]} {RDATA[2][9]} \
    {RDATA[2][8]} {RDATA[2][7]} {RDATA[2][6]} {RDATA[2][5]} {RDATA[2][4]} {RDATA[2][3]} {RDATA[2][2]} {RDATA[2][1]} \
    {RDATA[2][0]} {RRESP[2][1]} {RRESP[2][0]} {RLAST[2]} {RVALID[2]} {RREADY[2]} {REGS_WE[2]} {REGS_WADDR[2][3]} \
    {REGS_WADDR[2][2]} {REGS_WADDR[2][1]} {REGS_WADDR[2][0]} {REGS_WDATA[2][15]} {REGS_WDATA[2][14]} {REGS_WDATA[2][13]} {REGS_WDATA[2][12]} {REGS_WDATA[2][11]} \
    {REGS_WDATA[2][10]} {REGS_WDATA[2][9]} {REGS_WDATA[2][8]} {REGS_WDATA[2][7]} {REGS_WDATA[2][6]} {REGS_WDATA[2][5]} {REGS_WDATA[2][4]} {REGS_WDATA[2][3]} \
    {REGS_WDATA[2][2]} {REGS_WDATA[2][1]} {REGS_WDATA[2][0]} {REGS_WSTRB[2][1]} {REGS_WSTRB[2][0]} {REGS_RADDR[2][3]} {REGS_RADDR[2][2]} {REGS_RADDR[2][1]} \
    {REGS_RADDR[2][0]} {REGS_RDATA[2][15]} {REGS_RDATA[2][14]} {REGS_RDATA[2][13]} {REGS_RDATA[2][12]} {REGS_RDATA[2][11]} {REGS_RDATA[2][10]} {REGS_RDATA[2][9]} \
    {REGS_RDATA[2][8]} {REGS_RDATA[2][7]} {REGS_RDATA[2][6]} {REGS_RDATA[2][5]} {REGS_RDATA[2][4]} {REGS_RDATA[2][3]} {REGS_RDATA[2][2]} {REGS_RDATA[2][1]} \
    {REGS_RDATA[2][0]} \
}

editPin -pin $pins_left   -side LEFT   -layer M4 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection clockwise
editPin -pin $pins_right  -side RIGHT  -layer M4 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection counterclockwise
editPin -pin $pins_top    -side TOP    -layer M3 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection clockwise
editPin -pin $pins_bottom -side BOTTOM -layer M3 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection counterclockwise
set pins_left {\
    {AWID[1][1]} {AWID[1][0]} {AWADDR[1][7]} {AWADDR[1][6]} {AWADDR[1][5]} {AWADDR[1][4]} {AWADDR[1][3]} {AWADDR[1][2]} \
    {AWADDR[1][1]} {AWADDR[1][0]} {AWLEN[1][3]} {AWLEN[1][2]} {AWLEN[1][1]} {AWLEN[1][0]} {AWBURST[1][1]} {AWBURST[1][0]} \
    {AWQOS[1][3]} {AWQOS[1][2]} {AWQOS[1][1]} {AWQOS[1][0]} {AWVALID[1]} {AWREADY[1]} {WDATA[1][15]} {WDATA[1][14]} \
    {WDATA[1][13]} {WDATA[1][12]} {WDATA[1][11]} {WDATA[1][10]} {WDATA[1][9]} {WDATA[1][8]} {WDATA[1][7]} {WDATA[1][6]} \
    {WDATA[1][5]} {WDATA[1][4]} {WDATA[1][3]} {WDATA[1][2]} {WDATA[1][1]} {WDATA[1][0]} {WSTRB[1][1]} {WSTRB[1][0]} \
    {WLAST[1]} {WVALID[1]} {WREADY[1]} {BID[1][1]} {BID[1][0]} {BRESP[1][1]} {BRESP[1][0]} {BVALID[1]} \
    {BREADY[1]} {ARID[1][1]} {ARID[1][0]} {ARADDR[1][7]} {ARADDR[1][6]} {ARADDR[1][5]} {ARADDR[1][4]} {ARADDR[1][3]} \
    {ARADDR[1][2]} {ARADDR[1][1]} {ARADDR[1][0]} {ARLEN[1][3]} {ARLEN[1][2]} {ARLEN[1][1]} {ARLEN[1][0]} {ARBURST[1][1]} \
    {ARBURST[1][0]} {ARQOS[1][3]} {ARQOS[1][2]} {ARQOS[1][1]} {ARQOS[1][0]} {ARVALID[1]} {ARREADY[1]} {RID[1][1]} \
    {RID[1][0]} {RDATA[1][15]} {RDATA[1][14]} {RDATA[1][13]} {RDATA[1][12]} {RDATA[1][11]} {RDATA[1][10]} {RDATA[1][9]} \
    {RDATA[1][8]} {RDATA[1][7]} {RDATA[1][6]} {RDATA[1][5]} {RDATA[1][4]} {RDATA[1][3]} {RDATA[1][2]} {RDATA[1][1]} \
    {RDATA[1][0]} {RRESP[1][1]} {RRESP[1][0]} {RLAST[1]} {RVALID[1]} {RREADY[1]} \
}

set pins_right {\
    ACLK ARESETn {REGS_WE[1]} {REGS_WADDR[1][3]} {REGS_WADDR[1][2]} {REGS_WADDR[1][1]} {REGS_WADDR[1][0]} {REGS_WDATA[1][15]} \
    {REGS_WDATA[1][14]} {REGS_WDATA[1][13]} {REGS_WDATA[1][12]} {REGS_WDATA[1][11]} {REGS_WDATA[1][10]} {REGS_WDATA[1][9]} {REGS_WDATA[1][8]} {REGS_WDATA[1][7]} \
    {REGS_WDATA[1][6]} {REGS_WDATA[1][5]} {REGS_WDATA[1][4]} {REGS_WDATA[1][3]} {REGS_WDATA[1][2]} {REGS_WDATA[1][1]} {REGS_WDATA[1][0]} {REGS_WSTRB[1][1]} \
    {REGS_WSTRB[1][0]} {REGS_RADDR[1][3]} {REGS_RADDR[1][2]} {REGS_RADDR[1][1]} {REGS_RADDR[1][0]} {REGS_RDATA[1][15]} {REGS_RDATA[1][14]} {REGS_RDATA[1][13]} \
    {REGS_RDATA[1][12]} {REGS_RDATA[1][11]} {REGS_RDATA[1][10]} {REGS_RDATA[1][9]} {REGS_RDATA[1][8]} {REGS_RDATA[1][7]} {REGS_RDATA[1][6]} {REGS_RDATA[1][5]} \
    {REGS_RDATA[1][4]} {REGS_RDATA[1][3]} {REGS_RDATA[1][2]} {REGS_RDATA[1][1]} {REGS_RDATA[1][0]} \
}

set pins_top {\
    {AWID[0][1]} {AWID[0][0]} {AWADDR[0][7]} {AWADDR[0][6]} {AWADDR[0][5]} {AWADDR[0][4]} {AWADDR[0][3]} {AWADDR[0][2]} \
    {AWADDR[0][1]} {AWADDR[0][0]} {AWLEN[0][3]} {AWLEN[0][2]} {AWLEN[0][1]} {AWLEN[0][0]} {AWBURST[0][1]} {AWBURST[0][0]} \
    {AWQOS[0][3]} {AWQOS[0][2]} {AWQOS[0][1]} {AWQOS[0][0]} {AWVALID[0]} {AWREADY[0]} {WDATA[0][15]} {WDATA[0][14]} \
    {WDATA[0][13]} {WDATA[0][12]} {WDATA[0][11]} {WDATA[0][10]} {WDATA[0][9]} {WDATA[0][8]} {WDATA[0][7]} {WDATA[0][6]} \
    {WDATA[0][5]} {WDATA[0][4]} {WDATA[0][3]} {WDATA[0][2]} {WDATA[0][1]} {WDATA[0][0]} {WSTRB[0][1]} {WSTRB[0][0]} \
    {WLAST[0]} {WVALID[0]} {WREADY[0]} {BID[0][1]} {BID[0][0]} {BRESP[0][1]} {BRESP[0][0]} {BVALID[0]} \
    {BREADY[0]} {ARID[0][1]} {ARID[0][0]} {ARADDR[0][7]} {ARADDR[0][6]} {ARADDR[0][5]} {ARADDR[0][4]} {ARADDR[0][3]} \
    {ARADDR[0][2]} {ARADDR[0][1]} {ARADDR[0][0]} {ARLEN[0][3]} {ARLEN[0][2]} {ARLEN[0][1]} {ARLEN[0][0]} {ARBURST[0][1]} \
    {ARBURST[0][0]} {ARQOS[0][3]} {ARQOS[0][2]} {ARQOS[0][1]} {ARQOS[0][0]} {ARVALID[0]} {ARREADY[0]} {RID[0][1]} \
    {RID[0][0]} {RDATA[0][15]} {RDATA[0][14]} {RDATA[0][13]} {RDATA[0][12]} {RDATA[0][11]} {RDATA[0][10]} {RDATA[0][9]} \
    {RDATA[0][8]} {RDATA[0][7]} {RDATA[0][6]} {RDATA[0][5]} {RDATA[0][4]} {RDATA[0][3]} {RDATA[0][2]} {RDATA[0][1]} \
    {RDATA[0][0]} {RRESP[0][1]} {RRESP[0][0]} {RLAST[0]} {RVALID[0]} {RREADY[0]} {REGS_WE[0]} {REGS_WADDR[0][3]} \
    {REGS_WADDR[0][2]} {REGS_WADDR[0][1]} {REGS_WADDR[0][0]} {REGS_WDATA[0][15]} {REGS_WDATA[0][14]} {REGS_WDATA[0][13]} {REGS_WDATA[0][12]} {REGS_WDATA[0][11]} \
    {REGS_WDATA[0][10]} {REGS_WDATA[0][9]} {REGS_WDATA[0][8]} {REGS_WDATA[0][7]} {REGS_WDATA[0][6]} {REGS_WDATA[0][5]} {REGS_WDATA[0][4]} {REGS_WDATA[0][3]} \
    {REGS_WDATA[0][2]} {REGS_WDATA[0][1]} {REGS_WDATA[0][0]} {REGS_WSTRB[0][1]} {REGS_WSTRB[0][0]} {REGS_RADDR[0][3]} {REGS_RADDR[0][2]} {REGS_RADDR[0][1]} \
    {REGS_RADDR[0][0]} {REGS_RDATA[0][15]} {REGS_RDATA[0][14]} {REGS_RDATA[0][13]} {REGS_RDATA[0][12]} {REGS_RDATA[0][11]} {REGS_RDATA[0][10]} {REGS_RDATA[0][9]} \
    {REGS_RDATA[0][8]} {REGS_RDATA[0][7]} {REGS_RDATA[0][6]} {REGS_RDATA[0][5]} {REGS_RDATA[0][4]} {REGS_RDATA[0][3]} {REGS_RDATA[0][2]} {REGS_RDATA[0][1]} \
    {REGS_RDATA[0][0]} \
}

set pins_bottom {\
    {AWID[2][1]} {AWID[2][0]} {AWADDR[2][7]} {AWADDR[2][6]} {AWADDR[2][5]} {AWADDR[2][4]} {AWADDR[2][3]} {AWADDR[2][2]} \
    {AWADDR[2][1]} {AWADDR[2][0]} {AWLEN[2][3]} {AWLEN[2][2]} {AWLEN[2][1]} {AWLEN[2][0]} {AWBURST[2][1]} {AWBURST[2][0]} \
    {AWQOS[2][3]} {AWQOS[2][2]} {AWQOS[2][1]} {AWQOS[2][0]} {AWVALID[2]} {AWREADY[2]} {WDATA[2][15]} {WDATA[2][14]} \
    {WDATA[2][13]} {WDATA[2][12]} {WDATA[2][11]} {WDATA[2][10]} {WDATA[2][9]} {WDATA[2][8]} {WDATA[2][7]} {WDATA[2][6]} \
    {WDATA[2][5]} {WDATA[2][4]} {WDATA[2][3]} {WDATA[2][2]} {WDATA[2][1]} {WDATA[2][0]} {WSTRB[2][1]} {WSTRB[2][0]} \
    {WLAST[2]} {WVALID[2]} {WREADY[2]} {BID[2][1]} {BID[2][0]} {BRESP[2][1]} {BRESP[2][0]} {BVALID[2]} \
    {BREADY[2]} {ARID[2][1]} {ARID[2][0]} {ARADDR[2][7]} {ARADDR[2][6]} {ARADDR[2][5]} {ARADDR[2][4]} {ARADDR[2][3]} \
    {ARADDR[2][2]} {ARADDR[2][1]} {ARADDR[2][0]} {ARLEN[2][3]} {ARLEN[2][2]} {ARLEN[2][1]} {ARLEN[2][0]} {ARBURST[2][1]} \
    {ARBURST[2][0]} {ARQOS[2][3]} {ARQOS[2][2]} {ARQOS[2][1]} {ARQOS[2][0]} {ARVALID[2]} {ARREADY[2]} {RID[2][1]} \
    {RID[2][0]} {RDATA[2][15]} {RDATA[2][14]} {RDATA[2][13]} {RDATA[2][12]} {RDATA[2][11]} {RDATA[2][10]} {RDATA[2][9]} \
    {RDATA[2][8]} {RDATA[2][7]} {RDATA[2][6]} {RDATA[2][5]} {RDATA[2][4]} {RDATA[2][3]} {RDATA[2][2]} {RDATA[2][1]} \
    {RDATA[2][0]} {RRESP[2][1]} {RRESP[2][0]} {RLAST[2]} {RVALID[2]} {RREADY[2]} {REGS_WE[2]} {REGS_WADDR[2][3]} \
    {REGS_WADDR[2][2]} {REGS_WADDR[2][1]} {REGS_WADDR[2][0]} {REGS_WDATA[2][15]} {REGS_WDATA[2][14]} {REGS_WDATA[2][13]} {REGS_WDATA[2][12]} {REGS_WDATA[2][11]} \
    {REGS_WDATA[2][10]} {REGS_WDATA[2][9]} {REGS_WDATA[2][8]} {REGS_WDATA[2][7]} {REGS_WDATA[2][6]} {REGS_WDATA[2][5]} {REGS_WDATA[2][4]} {REGS_WDATA[2][3]} \
    {REGS_WDATA[2][2]} {REGS_WDATA[2][1]} {REGS_WDATA[2][0]} {REGS_WSTRB[2][1]} {REGS_WSTRB[2][0]} {REGS_RADDR[2][3]} {REGS_RADDR[2][2]} {REGS_RADDR[2][1]} \
    {REGS_RADDR[2][0]} {REGS_RDATA[2][15]} {REGS_RDATA[2][14]} {REGS_RDATA[2][13]} {REGS_RDATA[2][12]} {REGS_RDATA[2][11]} {REGS_RDATA[2][10]} {REGS_RDATA[2][9]} \
    {REGS_RDATA[2][8]} {REGS_RDATA[2][7]} {REGS_RDATA[2][6]} {REGS_RDATA[2][5]} {REGS_RDATA[2][4]} {REGS_RDATA[2][3]} {REGS_RDATA[2][2]} {REGS_RDATA[2][1]} \
    {REGS_RDATA[2][0]} \
}

editPin -pin $pins_left   -side LEFT   -layer M4 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection clockwise
editPin -pin $pins_right  -side RIGHT  -layer M4 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection counterclockwise
editPin -pin $pins_top    -side TOP    -layer M3 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection clockwise
editPin -pin $pins_bottom -side BOTTOM -layer M3 -spreadType SIDE -pinWidth 0.018 -pinDepth 0.5 -spreadDirection counterclockwise

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}

setAddStripeMode -stacked_via_bottom_layer M1 \
    -stacked_via_top_layer M2

sroute -connect { blockPin padPin padRing corePin floatingStripe } \
    -layerChangeRange { M1 M7 } \
    -blockPinTarget { nearestTarget } \
    -padPinPortConnect { allPort oneGeom } \
    -padPinTarget { nearestTarget } \
    -corePinTarget { firstAfterRowEnd } \
    -floatingStripeTarget { blockring padring ring stripe ringpin blockpin followpin } \
    -allowJogging 1 \
    -crossoverViaLayerRange { M1 M7 } \
    -nets { VDD VSS } \
    -allowLayerChange 1 \
    -blockPin useLef \
    -targetViaLayerRange { M1 M7 }

### Intervene Here. Manually fix the Top M1 Follow Rail

source "tcl/m2followRail.tcl"

setViaGenMode -viarule_preference { M6_M5widePWR1p152 M5_M4widePWR0p864 M4_M3widePWR0p864 }

# ! VALUES BELOW ADJUSTED FOR 1x TECH (pitches M3=0.036 M4/M5=0.048 M6=0.064)

# has to be 5, 9, 13, ... change the 8 to widen by 4 min widths
set m3pwrwidth [expr 0.018 * (5 + (4 * 2))]
set m3pwrset2settracks  60
set m3pwrset2setdist    [expr $m3pwrset2settracks * 0.036]
print "M3 PWR width and set to set distance: $m3pwrwidth $m3pwrset2setdist"

# must be odd multiple of width and space so we stay on grid
set m3pwrspacing [expr 0.018 * 21]

# the xoffset specifies the left edge of the 1st wire.
set m3pwrxoffset [expr (0.018 * 26) + 0.009]
print "M3 PWR spacing and offset: $m3pwrspacing $m3pwrxoffset"

addStripe -extend_to design_boundary \
    -skip_via_on_wire_shape Noshape \
    -max_same_layer_jog_length 0 \
    -set_to_set_distance $m3pwrset2setdist \
    -skip_via_on_pin Standardcell \
    -stacked_via_top_layer M7 \
    -spacing $m3pwrspacing \
    -xleft_offset $m3pwrxoffset \
    -merge_stripes_value 0.04 \
    -layer M3 \
    -width $m3pwrwidth \
    -nets {VDD VSS} \
    -stacked_via_bottom_layer M2

set m4pwrwidth [expr 0.024 * (5 + (4 * 1))]
set m4pwrset2settracks  80
set m4pwrset2setdist    [expr $m4pwrset2settracks * 0.048]
print "M4 PWR width and set to set distance: $m4pwrwidth $m4pwrset2setdist"

set m4pwrspacing [expr 0.048 * 10]
set m4pwrxoffset [expr 0.003 + 0.048 * 13]
print "M4 PWR spacing and offset: $m4pwrspacing $m4pwrxoffset"

setAddStripeMode \
    -max_via_size { Stripe 100 100 100 } \
    -via_using_exact_crossover_size true \
    -stacked_via_bottom_layer M3 \
    -stacked_via_top_layer M4 \
    -trim_antenna_back_to_shape stripe

addStripe -extend_to design_boundary \
    -direction horizontal \
    -skip_via_on_wire_shape Noshape \
    -max_same_layer_jog_length 0 \
    -set_to_set_distance $m4pwrset2setdist \
    -skip_via_on_pin Standardcell \
    -spacing $m4pwrspacing \
    -start_offset $m4pwrxoffset \
    -merge_stripes_value 0.04 \
    -layer M4 \
    -width $m4pwrwidth \
    -nets {VDD VSS}

set m5pwrwidth [expr 0.024 * (5 + (4 * 1))]
set m5pwrset2settracks  80
set m5pwrset2setdist    [expr $m5pwrset2settracks * 0.048]
print "M5 PWR width and set to set distance: $m5pwrwidth $m5pwrset2setdist"

set m5pwrspacing [expr 0.024 * 21]
set m5pwrxoffset [expr (0.024 * 70) + 0.012]
print "M5 PWR spacing and offset: $m5pwrspacing $m5pwrxoffset"

setAddStripeMode -stacked_via_bottom_layer M4 \
    -stacked_via_top_layer M5

setViaGenMode -bar_cut_orientation horizontal

addStripe -extend_to design_boundary \
    -direction vertical \
    -skip_via_on_wire_shape Noshape \
    -max_same_layer_jog_length 0 \
    -set_to_set_distance $m5pwrset2setdist \
    -skip_via_on_pin Standardcell \
    -spacing $m5pwrspacing \
    -start_offset $m5pwrxoffset \
    -merge_stripes_value 0.04 \
    -layer M5 \
    -width $m5pwrwidth \
    -nets {VDD VSS}

set m6pwrwidth [expr 0.032 * (5 + (4 * 1))]
set m6pwrset2settracks  60
set m6pwrset2setdist    [expr $m6pwrset2settracks * 0.064]
print "M6 PWR width and set to set distance: $m6pwrwidth $m6pwrset2setdist"

set m6pwrspacing [expr 0.032 * 21]
set m6pwrxoffset [expr (0.032 * 50) + 0.002]
print "M6 PWR spacing and offset: $m6pwrspacing $m6pwrxoffset"

setAddStripeMode -stacked_via_bottom_layer M5 \
    -stacked_via_top_layer M6

setViaGenMode -bar_cut_orientation vertical

addStripe -extend_to design_boundary \
    -direction horizontal \
    -skip_via_on_wire_shape Noshape \
    -max_same_layer_jog_length 0 \
    -set_to_set_distance $m6pwrset2setdist \
    -skip_via_on_pin Standardcell \
    -spacing $m6pwrspacing \
    -start_offset $m6pwrxoffset \
    -merge_stripes_value 0.04 \
    -layer M6 \
    -width $m6pwrwidth \
    -nets {VDD VSS}

#timeDesign -prePlace

createBasicPathGroups

setMaxRouteLayer 6
source "tcl/cts_legacy_fill.tcl"
file mkdir pnr/reports
verify_connectivity -nets {VDD VSS} -type special > pnr/reports/con.rpt
source "tcl/report_legacy.tcl"
win
