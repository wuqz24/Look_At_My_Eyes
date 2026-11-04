cd {D:/fpga/HX1P35/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display_Runs/syn_1}
if {[catch {source D:/Anlogic/TD_6.2.1/doc/scripts/DefaultFlow.tcl} result]} {
  puts "BUILD_FAILED: $result"
  exit 1
}
puts "BUILD_COMPLETE"
exit 0
