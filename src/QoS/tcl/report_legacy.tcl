##############################################################################
# report_legacy.tcl  --  LEGACY Innovus UI
#
#   source tcl/report_legacy.tcl
##############################################################################

# output directory for this run
set RPT pnr/reports
file mkdir pnr
file mkdir $RPT

# --- parasitic extraction (post-route, signoff-quality) ---------------------
#setExtractRCMode -engine postRoute -effortLevel high
#extractRC

# --- timing -----------------------------------------------------------------
# timing is not extraction-valid without QRC/captable; report from synthesis instead.
# these are kept only as a routed-geometry sanity check (NOT signoff).
# NOTE: without QRC/captable these are NOT extraction-valid (PreRoute estimate).
# Reported for completeness; take signoff timing from synthesis.
report_timing -late   > $RPT/setup_timing.rpt
report_timing -early  > $RPT/hold_timing.rpt
#report_timing_summary > $RPT/timing_summary.rpt

# --- area -------------------------------------------------------------------
report_area  > $RPT/area.rpt

# --- power ------------------------------------------------------------------
report_power > $RPT/power.rpt

puts "=============================================="
puts " Reports written to: $RPT"
puts "=============================================="
