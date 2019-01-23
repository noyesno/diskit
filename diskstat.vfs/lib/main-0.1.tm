# vim:set syntax=tcl sw=2: #

package require tcllib
package require tepam

package provide main 0.1

namespace eval main {
  
}

proc main {args} {

  set argc [llength $args]

  switch -- $argc {
    0 {
      set argv [lassign $::argv name]
      set main ::main::$name

      if {[info commands $main] eq ""} {
        set main ::main::help
      }
      return [uplevel #0 $main {*}$argv]
    }
    3 {
      set args [lassign $args name]
      return [::tepam::procedure ::main::$name {*}$args]
    }
    default {
      error "invalid arguments for main"
    }
  }
}

main help {} {
  puts "help $::argv"
}
