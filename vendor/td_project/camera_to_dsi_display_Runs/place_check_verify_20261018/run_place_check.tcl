cd {D:/fpga/HX1P35/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display_Runs/place_check_verify_20261018}
if {[catch {source {D:/fpga/HX1P35/HX1P35_Tracker/vendor/td_project/camera_to_dsi_display_Runs/place_check_verify_20261018/camera_to_dsi_display.tcl}} result]} {
  puts "PLACE_CHECK_FAILED: $result"
  exit 1
}
puts "PLACE_CHECK_COMPLETE: placement only; route and bitgen were not run"
exit 0
