cd {D:/fpga/HX1P35/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display_Runs/syn_current_20261021}
if {[catch {source D:/Anlogic/TD_6.2.1/doc/scripts/DefaultFlow.tcl} result]} {
  puts "CURRENT_SYNTHESIS_FAILED: $result"
  exit 1
}
puts "CURRENT_SYNTHESIS_COMPLETE"
exit 0
