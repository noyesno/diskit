# vim:set syntax=tcl: #

package provide lockfile 0.1

# lockfile -sleeptime | -r retries | -l locktimeout | -s suspend | -! | filename ...

proc lockfile {args} {
  array set kargs {
    @    ""
    -l   0
    -m   ""
    -var ""
  }
  set argskip 0
  set argidx  0
  foreach arg $args {
    incr argidx
    if {$argskip} {
      incr argskip -1
      continue
    }

    if {[string match "-*" $arg]} {
      set kargs($arg) [lindex $args $argidx]
      incr argskip
    } else {
      lappend kargs(@) $arg
    }
  }

  set lockfile [lindex $kargs(@) 0]

  if {$kargs(-var) ne ""} {
    upvar $kargs(-var) lockstat
  }
  set lockstat ""

  # TODO: retry n times -r


  # TODO: use nsfile:: !!!
  while {[file exist $lockfile]} {

    if {[file size $lockfile]==0} {
      file delete -force $lockfile
      break
    }

    array set payload {
      -l   0
    }

    set fp [open $lockfile "r"]
    array set payload [read $fp]
    close $fp

    set lockstat [array get payload]

    set now    [clock seconds]
    set mtime  [file mtime $lockfile]

    if { $payload(-l) > 0 && ($now-$mtime) > $payload(-l) } {
      file delete -force $lockfile
    }
    break
  }

  if {[file exist $lockfile]} {
    dict set lockstat status "locked"
    return 0
  }

  array unset payload
  array set payload [array get kargs]
  array set payload [list time [clock seconds]]
  set lockstat [array get payload]
  try {
    set flock [open $lockfile "CREAT EXCL WRONLY"]
    puts $flock [array get payload]
    close $flock
    return 1
  } on error err {
    dict set lockstat status "fail"
    dict set lockstat error  $err
    return 0
  }
}

