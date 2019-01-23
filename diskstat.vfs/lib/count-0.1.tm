# vim:set syntax=tcl sw=2 :#

package provide count 0.1

namespace eval count {
  variable data ; array set data ""

  proc reset {} {
    variable data
    array unset data
  }

  proc value {key args} {
    variable data

    set old_value 0
    catch {
      set old_value $data($key)
    } 

    if {[llength $args]} {
      set value [lindex $args 0]
      set data($key) $value
    }

    return $old_value
  }

  proc incr {key value} {
    variable data
    ::incr data($key) $value
  }
}
