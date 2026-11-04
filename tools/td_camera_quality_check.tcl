set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root reports td_camera_quality]
file mkdir $output
cd [file join $root vendor td_project]
if {[catch {
    open_project [file join $root vendor td_project camera_to_dsi_display.al]
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    elaborate -top design_top_wrapper
} message]} {
    puts "FAIL camera_quality_elaborate: $message"
    exit 1
}
puts "PASS camera_quality_elaborate: production top; not P&R or timing signoff"
exit 0
