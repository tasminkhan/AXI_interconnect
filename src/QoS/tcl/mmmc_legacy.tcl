##############################################################################
## MMMC - ASAP7 RVT / TT / 0.7V / 25C, unscaled (1x)  -- LEGACY UI format
## Difference vs the Stylus version: no create_timing_condition (that command
## marks the mmmc as MMMC2 format, which legacy init_design rejects with
## IMPMEX-7044). The library set is attached straight to the delay corner.
##############################################################################

set pdk /projects/CM_BTAP/work/btapuser50ddc/pdks/asap7/asap7sc7p5t_28
set syn /projects/CM_BTAP/work/btapuser50ddc/axi/QoS/syn/outputs

##############################################################################
## LIBRARY SET
##############################################################################
create_library_set -name typical_lib -timing [list \
    $pdk/LIB/CCS/asap7sc7p5t_AO_RVT_TT_ccs_211120.lib     \
    $pdk/LIB/CCS/asap7sc7p5t_INVBUF_RVT_TT_ccs_220122.lib \
    $pdk/LIB/CCS/asap7sc7p5t_OA_RVT_TT_ccs_211120.lib     \
    $pdk/LIB/CCS/asap7sc7p5t_SEQ_RVT_TT_ccs_220123.lib    \
    $pdk/LIB/CCS/asap7sc7p5t_SIMPLE_RVT_TT_ccs_211120.lib ]

##############################################################################
## RC CORNER  (QRC tech file attached here)
##############################################################################
create_rc_corner -name rc_typical \
    -temperature 25 
    
##############################################################################
## DELAY CORNER  (legacy: library_set attached directly, no timing_condition)
##############################################################################
create_delay_corner -name typical_delay \
    -library_set typical_lib \
    -rc_corner   rc_typical

##############################################################################
## CONSTRAINT MODE
##############################################################################
create_constraint_mode -name constraint \
    -sdc_files [list $syn/top_asap7_ccs.sdc]

##############################################################################
## ANALYSIS VIEW
##############################################################################
create_analysis_view -name typical_view \
    -constraint_mode constraint \
    -delay_corner    typical_delay

##############################################################################
## ACTIVE VIEW
##############################################################################
set_analysis_view -setup { typical_view } -hold { typical_view }
