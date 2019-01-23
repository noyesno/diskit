# vim:set syntax=tcl sw=2 :#

package provide parallel 0.1

namespace eval parallel {
  variable process [dict create]
  variable count 0
  variable config
  array set config {
    -maxworkers 4
  }

  dict set process queue [list]

  proc debug {message} {
    set datetime [clock format [clock seconds] -format "%Y-%m-%dT%T"]
    puts "debug: $datetime $message"
  }

  proc post {tpool args} {
    variable process
    variable count
    variable config

    set command [lindex $args end]

    if {"-nowait" in $args} {
      dict lappend process queue $command
      return
    }

    if {"-detached" in $args} {
      # TODO:
    }

    wait_worker $tpool

    set pid [spawn $tpool $command]
    return $pid
  }

  proc wait_worker {tpool} {
    variable config
    variable count

    while {$count >= $config(-maxworkers)} {
      debug "wait worker"
      vwait ::parallel::count
    }
    return
  }

  proc wait_all {tpool} {
    variable config
    variable count

    while {$count>0} {
      vwait ::parallel::count
    }
  }

  proc get {tpool job} {
    # TODO:
  }

  # TODO:
  proc wait {tpool joblist {varname ""}} {
    variable config
    variable count

    while {$count>0} {
      vwait ::parallel::count
    }
  }

  # TODO:
  proc cancel {tpool joblist {varname ""}} {
    variable config
    variable count

    while {$count>0} {
      vwait ::parallel::count
    }
  }

  proc spawn {tpool {command ""}} {
    variable process
    variable count

    if {$command eq ""} {
      set tasks [dict get $process queue]

      set command [lindex $tasks 0]
      dict set process queue [lrange $tasks 1 end]
    }

    if {$command eq ""} {
      return
    }

    set fpipe [open "| $command 2>@1" "r"]
    puts "fpipe = [fconfigure $fpipe]"
    fconfigure $fpipe -blocking 0
    set ns [namespace current]
    lassign [pid $fpipe] pid

    fileevent $fpipe readable [list ${ns}::pipe_read $tpool $fpipe $pid]

    dict set process pid:$pid ""

    incr count

    debug "process $pid spawn $command"

    return $pid
  }

  proc recycle {tpool pid} {
    variable process
    variable count

    debug "process $pid recycle"
    incr count -1

    after 100  ;# sleep 100ms

    spawn $tpool
  }

  proc pipe_read {tpool fpipe pid args} {
    variable process

    while {[gets $fpipe line]>=0} {
      puts $line
    }

    if {[eof $fpipe]} {
      fileevent $fpipe readable ""

      if [catch {close $fpipe}] {
        dict set process pid:$pid result 1
      } else {
        dict set process pid:$pid result 0
      }
      recycle $tpool $pid
    }
    return
  }

}

