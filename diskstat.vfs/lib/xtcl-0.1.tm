# vim:set syntax=tcl sw=2 :#

package provide xtcl 0.1


proc dictget {dict args} {

  if {[llength $args]==1} {
    set defval ""
    set result $defval
    catch { set result [dict get $dict [lindex $args 0]] }
  } else {
    set defval [lindex $args end]
    set result $defval
    catch { set result [dict get $dict {*}[lrange $args 0 end-1]] }
  }

  return $result
}


proc trydo {body} {
  foreach - 1 {
    uplevel $body
  }
}

