# vim:set syntax=tcl sw=2 :#

package provide markstack 0.1

namespace eval markstack {
  variable stack    [list]
  variable topmarks [dict create]

  proc push {data marks} {
    variable stack
    variable topmarks

    lappend stack [list $data $marks ""]

    foreach {mark value} $marks {
      dict set topmarks $mark $value
    }
  }

  proc mark {args} {
    variable stack
    variable topmarks

    if {[llength $args]==1} {
      set marks [lindex $args 0]
    } else {
      set marks $args
    }

    set topmark [lindex $stack end 1]
    lappend topmark {*}$marks
    lset stack end 1 $topmark

    foreach {mark value} $marks {
      dict set topmarks $mark $value
    }

  }

  proc pop {} {
    variable stack
    variable topmarks

    set result [lindex $stack end]
    set stack [lreplace $stack [set stack end] end]

    foreach {mark value} [lindex $result 1] {
      dict unset topmarks $mark
    }

    return $result
  }

  proc has {mark} {
    variable topmarks
    return [dict exist $topmarks $mark]
  }

  proc get {mark} {
    variable topmarks
    return [dict get $topmarks $mark]
  }

  proc cset {name value} {
    variable stack

    set meta [lindex $stack end 2]
    dict set meta $name $value
    lset stack end 2 $meta
    return
  }

  proc cget {name} {
    variable stack

    set result ""
    catch {
      set result [dict get [lindex $stack end 2] $name]
    }
    return $result
  }

}

if {[file normalize $::argv0] ne [file normalize [info script]]} {
  return
}

