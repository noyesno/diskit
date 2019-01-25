# vim:set syntax=tcl sw=2: #

set KIT_ROOT [file dir [info script]]
set KIT_LIB  [file join $KIT_ROOT lib]

set ::auto_path [linsert $::auto_path 0 $KIT_LIB]
::tcl::tm::path add $KIT_LIB

package require diskstat

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
        package require diskstat

	dirstat::update_dbfile $dbfile {*}$args
    }

}

package require main

#  -description ""
#  -example ""

main update {
  -short_description "update a single diskstat database"
  -named_arguments_first 0
  -args {
    { dbfile -type string             -description "path to database file" }
    { -dir    -type string -default "" -description "disk dir path" }
    { -conf   -type string -default "" -description "config" }
  }
} {

  set conf "-dirs $dir"
  task::update $dbfile -dir $dir -conf $conf

  return

  global tpool

  set tpool [tpool::create -minworkers 2 -maxworkers 5 -initcmd { package require Ttrace ; thread_init }]
  set tid [tpool::post $tpool [list task::update $dbfile {*}$args]]
  tpool::wait $tpool $tid
  tpool::get $tpool $tid
}

main update-many {
  -short_description "update multiple diskstat database"
  -description ""
  -example ""
  -named_arguments_first 0
  -args {
    {cfgfile -type string}
  }
} {
  global tpool

  set joblist [list]

  source $cfgfile

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

main update-config {
  -short_description "update diskstat database listed in config file"
  -description ""
  -example ""
  -named_arguments_first 0
  -args {
    {cfgfile -type string}
  }
} {
  main::update-parallel $cfgfile
}


main update-parallel {
  -short_description "update multiple diskstat database in parallel"
  -description ""
  -example ""
  -named_arguments_first 0
  -args {
    {cfgfile -type string}
  }
} {

  if {$cfgfile eq ""} {
    # TODO:
    set cfgfile "config.tcl"
  }

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

main "update-auto" {} {
    log_info "update start ..."
    set argv [lassign $act_argv dbfile]
    if {$dbfile eq ""} {
      main::update-parallel
      # main::update_many
    } else {
      main::update $dbfile {*}$argv
    }
}

main debug {} {
  global tpool

  set tid [tpool::post $tpool {
    package require diskstat
  }]

  tpool::wait $tpool $tid
  tpool::get $tpool $tid
}

main "decode" {
  -args {
    {dbfile -multiple -description "dbfile1 dbfile2 ..."}
  }
} {
  foreach item $dbfile {
    dirstat::decode $item
  }
}

main "find" {
  -args {
    {dbfile -description "dbfile"}
    {argv -multiple -default {} -description "options"}
  }
} {
  dirstat::find $dbfile {*}$argv
}

main "bigfile" {
  -args {
    {dbfile  -description "dbfile"}
    {outfile -type string  -default "" -description "output file"}
    {-decode -type none    -description "decode input dbfile"}
    {-sort   -type none    -description "sort output"}
    {-size   -type integer -default 300000 -description "big file size in KB"}
  }
} {

  array set ::kargs [list \
    -dbfile  $dbfile \
    -decode  $decode  \
    -sort    $sort    \
    -size    $size    \
    -outfile $outfile \
  ]

  uplevel #0 source $::KIT_ROOT/main/bigfile.tcl
}

main "readdir" {
  -args {
    {dir   -type string -description "disk dir"}
    {-stat -type none   -description "print stat info"}
  }
} {
  if {$stat} {
    puts [diskit::readdir -stat $dir]
  } else {
    puts [diskit::readdir $dir]
  }
}

main "statvfs" {
  -args {
    {dir -type string -description "disk dir"}
  }
} {
    puts [diskit::statvfs $dir]
}

main "test-tclx" {} {
  package require Tclx
  puts "[id]"
}

main

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

