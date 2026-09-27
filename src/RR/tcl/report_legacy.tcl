##############################################################################
# report_legacy.tcl  --  LEGACY Innovus UI
#
#   source tcl/report_legacy.tcl
##############################################################################

# output directory for this run
set RPT pnr/reports
exec mkdir -p $RPT

# --- parasitic extraction (post-route, signoff-quality) ---------------------
#setExtractRCMode -engine postRoute -effortLevel high
#extractRC

# --- timing -----------------------------------------------------------------
# timing is not extraction-valid without QRC/captable; report from synthesis instead.
 report_timing -late   > $RPT/setup_timing.rpt   ;# skipped: not extraction-valid without QRC
 report_timing -early  > $RPT/hold_timing.rpt    ;# take timing from synthesis instead
 report_timing_summary > $RPT/timing_summary.rpt

# --- area -------------------------------------------------------------------
report_area  > $RPT/area.rpt

# --- power ------------------------------------------------------------------
report_power > $RPT/power.rpt

puts "=============================================="
puts " Reports written to: $RPT"
puts "=============================================="
