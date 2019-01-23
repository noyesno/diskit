
set KIT_ROOT [file dir [info script]]
set KIT_LIB  [file join $KIT_ROOT lib]

set ::auto_path [linsert $::auto_path 0 $KIT_LIB]
::tcl::tm::path add $KIT_LIB

package require dirstat

package require Thread
package require Ttrace

namespace eval main {}
namespace eval task {}

package require parallel

if {[array get ::env HOSTNAME] eq ""} {
  array set ::env [list HOSTNAME [::exec [auto_execok hostname]]]
}

proc log_info {message} {
  set datetime [clock format [clock seconds] -format "%Y-%m-%dT%T"]
  puts "$datetime $::env(HOSTNAME) info: $message"
}

# TODO: use `interp bgerror` instead
proc bgerror {message} {
  set datetime [clock format [clock seconds] -format "%Y-%m-%dT%T"]
  puts "bgerror: $datetime $message"
}

ttrace::eval "
  proc thread_init {} {
    global argv0 KIT_ROOT KIT_LIB

    package require tclkit::init
    namespace eval task {}

    set argv0    {}
    set KIT_ROOT $::KIT_ROOT
    set KIT_LIB  $::KIT_LIB

    ::tcl::tm::path add \$KIT_LIB

    # TODO: skip this for starpack?
    set driver mk4
    package require \${driver}vfs
    set self \$KIT_ROOT
    ::vfs::\${driver}::Mount \$self \$self

  }
"

ttrace::eval {

    proc task::update {dbfile args} {
        package require dirstat

	dirstat::update_dbfile $dbfile {*}$args
    }

}


proc main::update {dbfile args} {
  task::update $dbfile {*}$args

  return

  global tpool

  set tpool [tpool::create -minworkers 2 -maxworkers 5 -initcmd { package require Ttrace ; thread_init }]
  set tid [tpool::post $tpool [list task::update $dbfile {*}$args]]
  tpool::wait $tpool $tid
  tpool::get $tpool $tid
}

proc main::update_many {} {
  global tpool

  set joblist [list]

  source $::KIT_ROOT/config.tcl
  source ./config.tcl
  dict for {name conf} $dirstat_tasks {
    set dbfile "dirstat-$name.db"
    set tid [tpool::post $tpool [list task::update $dbfile -conf $conf]]
    lappend joblist $tid
    puts stderr "thread $tid for $dbfile"
  }

  while {[llength $joblist]} {
    set done_jobs [tpool::wait $tpool $joblist pend_jobs]

    set jobs [dict create]
    foreach tid $joblist { dict set jobs $tid 1 }
    foreach tid $done_jobs {
      puts "thread $tid result = [tpool::get $tpool $tid]"
      dict unset jobs $tid
    }
    set joblist [dict keys $jobs]
  }

  return
}

proc main::update_parallel {{cfgfile "config.tcl"}} {

  set joblist [list]

  # TODO: use parallel::config -maxworkers 6
  set ::parallel::config(-maxworkers) 6

  source $cfgfile

  set tpool "parallel"

  puts stderr "process [pid] as master"
  dict for {name conf} $dirstat_tasks {
    set dbfile "dirstat-$name.db"

    set command [list tclkit $::argv0 update $dbfile -conf $conf]
    set tid [parallel::post $tpool $command]
    lappend joblist $tid
    puts stderr "process $tid for $dbfile"
  }

  parallel::wait_all $tpool
  return

  while {[llength $joblist]} {
    set done_jobs [process::wait $tpool $joblist pend_jobs]

    set jobs [dict create]
    foreach tid $joblist { dict set jobs $tid 1 }
    foreach tid $done_jobs {
      puts "process $tid result = [tpool::get $tpool $tid]"
      dict unset jobs $tid
    }
    set joblist [dict keys $jobs]
  }

  return
}

proc main::debug {} {
  global tpool

  set tid [tpool::post $tpool {
    package require dirstat
  }]

  tpool::wait $tpool $tid
  tpool::get $tpool $tid
}



set act_argv [lassign $::argv act]
switch -- $act {
  "scan" {
  }
  "update-config" {
    set argv [lassign $act_argv cfgfile]
    main::update_parallel $cfgfile
    # main::update_many
  }
  "update" {
    log_info "update start ..."
    set argv [lassign $act_argv dbfile]
    if {$dbfile eq ""} {
      main::update_parallel
      # main::update_many
    } else {
      main::update $dbfile {*}$argv
    }
  }
  "decode" {
    foreach dbfile $act_argv {
      dirstat::decode $dbfile
    }
  }
  "bigfile" {
    set ::argv $act_argv
    source $KIT_ROOT/main/bigfile.tcl
  }
  "readdir" {
    set argv [lassign $::argv -]
    puts [diskit::readir {*}$::argv]
  }
  "statvfs" {
    lassign $::argv - diskdir
    puts [diskit::statvfs $diskdir]
  }
  "debug" {
    main::debug
  }
  "tclx" {
    package require Tclx
    puts "[id]"
  }
  default {
    puts [{*}$::argv]
  }
}

exit



0x7fff   = 546  minutes
0x7fffff = 2330 hours

File Size
---------

awk '/^[FDRP]/ {a=length($0); k=$1; getline; b=length($0); sum[k,1]+=a; sum[k,2]+=b; sum[k,3]+=1;} END {for(k in sum) print k,sum[k]}' diskit-24x7.03.txt.4

R1 13356229
P1  4020557
D1 13386457
F1 11296254

R2 15184451
P2   948821
D2  7330890
F2  7024480


R3   948821
P3   948821
D3   949629
F3   559819

