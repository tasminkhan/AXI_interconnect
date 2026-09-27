##############################################################################
#  cts_legacy.tcl  --  LEGACY Innovus UI
#  Continuation of pnr_neuron_asap7_1x_legacy.tcl (after timeDesign -prePlace).
#  Follows official ASAP7 example_innovus.tcl. Placement -> CTS -> route ->
#  filler -> final checks. No GDS stream out.
#  Only legacy-confirmed commands (verifyGeometry for DRC; clock-report line
#  removed since the example only had it as a comment).
#
#  Run from the SAME legacy Innovus console:
#    source tcl/cts_legacy.tcl
##############################################################################

# placement pre-clock cts goes here...
setPlaceMode -place_global_uniform_density true
placeDesign
# optDesign -preCTS        ;# skipped: needs RC extraction (QRC unavailable)
# timeDesign -preCTS       ;# skipped: needs RC extraction (QRC unavailable)
# saveDesign DBS/place.enc

# CTS

setNanoRouteMode -drouteMinimizeLithoEffectOnLayer {f t t t t t t t t t} \
    -routeTopRoutingLayer 5 -routeBottomRoutingLayer 2 \
    -routeWithViaInPin true

# set desired clock cells here...
set_ccopt_property buffer_cells \
    {BUFx2_ASAP7_75t_R BUFx4_ASAP7_75t_R BUFx6f_ASAP7_75t_R \
     BUFx8_ASAP7_75t_R BUFx12_ASAP7_75t_R BUFx16f_ASAP7_75t_R}
set_ccopt_property inverter_cells \
    {INVx1_ASAP7_75t_R INVx2_ASAP7_75t_R INVx4_ASAP7_75t_R INVx8_ASAP7_75t_R}

set_ccopt_property target_skew 10ps
set_ccopt_property target_max_trans 60ps
setNanoRouteMode -routeTopRoutingLayer 5 -routeBottomRoutingLayer 2
create_route_type -name ccopt_route_group -bottom_preferred_layer 4 -top_preferred_layer 5
create_ccopt_clock_tree_spec
ccopt_design -cts

# report on clocks and check results
# timeDesign -postCTS      ;# skipped: needs RC extraction (QRC unavailable)
# saveDesign DBS/cts.enc

# optimize design as desired
# optDesign -postCTS       ;# skipped: needs RC extraction (QRC unavailable)
# optDesign -postCTS -hold ;# skipped: needs RC extraction (QRC unavailable)

# saveDesign DBS/cts_hold.enc

setNanoRouteMode -drouteMinimizeLithoEffectOnLayer {t t t t t t t t t t}

# -routeWithViaInPin true -- so it does not extend the M1 pins in cells

setNanoRouteMode -routeWithViaInPin true \
    -routeDesignFixClockNets true \
    -routeTopRoutingLayer 6

# route and optimize as desired
routeDesign
# optDesign -postRoute     ;# skipped: needs RC extraction (QRC unavailable)
# saveDesign DBS/route.enc

file mkdir pnr/reports
verifyConnectivity -type all -nets {VDD VSS} -report pnr/reports/conn_postroute.rpt
verifyGeometry -report pnr/reports/drc_postroute.rpt

# all done--finish up with decap and finally filler

#addFiller -cell {DECAPx10_ASAP7_75t_R} -prefix FILLER_DECAP_
#addFiller -cell {DECAPx6_ASAP7_75t_R}  -prefix FILLER_DECAP_
#addFiller -cell {DECAPx4_ASAP7_75t_R}  -prefix FILLER_DECAP_

addFiller -cell {TAPCELL_ASAP7_75t_R} -prefix FILLER_TAP_
#addFiller -cell {FILLER_ASAP7_75t_R FILLERxp5_ASAP7_75t_R} -prefix FILLER_

# --- METAL FILL (density) — only M1-M6, matches routed layers ---
#addMetalFill -layer {M1 M2 M3 M4 M5 M6} -timingAware on

# do your final checks and write the design out
verifyConnectivity -type all -report pnr/reports/conn_final.rpt
verifyGeometry -report pnr/reports/drc_final.rpt

# saveDesign DBS/final.enc

fit
