
package provide procstat 0.1

set NS procstat
namespace eval procstat {
  variable prev
  variable procstat
  array set prev ""
  array set procstat ""
  array set procstat {
    util ""
  }
  variable HZ

  proc readfile {file} {
    set fp [open $file "r"]
    set data [read $fp]
    close $fp
    return $data
  }

  proc guess_clock_tick {} {
    variable HZ

    lassign [readfile /proc/uptime] uptime_sec idle_sec

    set idle_tic [lindex [readfile /proc/stat] 4]
    set HZ [expr {ceil($idle_tic/$idle_sec)}]
    puts "debug: HZ = $HZ = $idle_tic/$idle_sec = [expr {$idle_tic/$idle_sec}]"

    if {0} {
      # This method has issue if this method is called a while later after process start.
      set starttime [lindex [readfile /proc/self/stat] 21]
      set HZ [expr {ceil($starttime/$uptime_sec)}]
    }

    return $HZ
  }

  guess_clock_tick
}

proc ${NS}::start {} {
  variable procstat
  cpu_util
  # puts $procstat(util)
  after 5000 [list ::procstat::start]
}

proc ${NS}::watch {{body ""}} {
  after 5000 [list ::procstat::watch $body]
}



proc ${NS}::cpu_util {} {
  variable prev
  variable procstat
  variable HZ

  set fp [open /proc/self/stat "r"]
  set data [read $fp]
  close $fp

  set utime     [lindex $data 13]
  set stime     [lindex $data 14]
  set cutime    [lindex $data 15]
  set cstime    [lindex $data 16]
  set starttime [lindex $data 21]

  set clock_sec [expr {[clock seconds]}] ;# ms = [clock milliseconds]
  set clock_tic [expr {($utime+$stime+$cutime+$cstime)}]

  set update [info exist prev(clock_tic)]
  if {$update} {
    set util  [expr {($clock_tic-$prev(clock_tic))*100.0/(($clock_sec-$prev(clock_sec))*$HZ)}]
    set procstat(util)  $util
  }

  set prev(clock_tic) $clock_tic
  set prev(clock_sec) $clock_sec


  return $procstat(util)
}

return

procstat::start

while 1 {
  incr n
  if {$n%1000==0} {
    after 1
    update
  }
}

vwait forever

