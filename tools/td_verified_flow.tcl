if {[catch {source D:/Anlogic/TD_6.2.1/doc/scripts/DefaultFlow.tcl} result]} {
    puts "BUILD_FAILED: $result"
    exit 1
}
puts "BUILD_COMPLETE"
exit 0
