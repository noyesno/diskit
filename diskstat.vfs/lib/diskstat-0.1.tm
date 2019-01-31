# vim:set syntax=tcl sw=2 :#

package require count
package require xtcl
package require diskit
package require frcode
package require markstack
package require lockfile

package provide diskstat 0.1

set NS dirstat

proc method {name argv body} "proc ${NS}::\$name \$argv \$body"

namespace eval dirstat {

}


proc ${NS}::log {args} {
  variable flog

  if {[llength $args]==1} {
    set message [lindex $args 0]
    if {$message ni "open close"} {
      puts $flog $message
      return
    }
  }

  set act [lindex $args 0]
  switch -- $act {
    "open" {
      set logfile [lindex $args 1]
      set flog [open $logfile "w"]
    }
    "close" {
      close $flog
    }
  }
  return ""
}

proc ${NS}::lock {dbfile} {
  set lockfile $dbfile.lock
  set ok [lockfile $lockfile -l [expr {3600*12}]]  ;# 12 hours
  return $ok
}

proc ${NS}::unlock {dbfile} {
  set lockfile $dbfile.lock
  file delete -force $lockfile

  return
}

proc ${NS}::decode {dbfile args} {

    set fp [open $dbfile]
    chan configure $fp -buffersize [expr 4096*16]  ;# 64 KB


    set lineno 0
    while {[gets $fp line]>=0} {
      incr lineno
      try {
      switch -glob -- $line {
	"#*" {
           set context ""
	   continue
	}
	"%*" {
           set context ""
           switch -- [lindex $line 1] {
             "root" {
               set cwd [lindex $line end]
             }
             "frcode" {
               set config(frcode) 1
             }
             "mtime_incr" {
               set config(mtime_incr) 1
             }
           }
	   continue
	}
	"R *" {
	  set dir [string range $line 2 end]

          frcode::prefix [file tail $dir]

	  lassign [gets $fp] - ksize mtime ztime_diff

          set dir_mtime $mtime
          set dir_ztime [expr {$mtime+$ztime_diff}]

          puts [list "R" $dir $ksize $mtime]
	}
	"F *" {
          if {$config(frcode)} {
            set idx [tcl_endOfWord $line 2]
            set prefix_diff [string range $line 2 $idx-1]
            set prefix_tail [string range $line $idx+1 end]
            set fname [frcode::prefix_append $prefix_diff $prefix_tail]
          } else {
	    set fname [string range $line 2 end]
          }

          set next_line [gets $fp]
	  lassign $next_line - ksize mtime atime size_kb
          incr lineno

          try {
            if {$config(mtime_incr)} {
              set mtime [expr {$dir_mtime+$mtime}]
              set atime [expr {$mtime+$atime}]
            }
          } on error err {
            puts stderr "Error: $lineno $line\n $next_line {$dir_mtime+$mtime}  {$mtime+$atime}" ; exit
          }

	  puts [list "F" $fname $ksize $mtime $atime]
	}
        "G*" -
        "X*" {
          # for a group of file, e.g. small files.
	  set fname [string range $line 2 end]
	  lassign [gets $fp] - count ksize mtime atime size_kb

          if {$config(mtime_incr)} {
            set mtime [expr {$dir_mtime+$mtime}]
            set atime [expr {$mtime+$atime}]
          }

	  puts "X $fname $count $ksize $mtime $atime"
        }
	"D *" {
          if {$config(frcode)} {
            set idx [tcl_endOfWord $line 2]
            set prefix_diff [string range $line 2 $idx-1]
            set prefix_tail [string range $line $idx+1 end]
            set dname [frcode::prefix_append $prefix_diff $prefix_tail]
          } else {
	    set dname [string range $line 2 end]
          }

	  lassign [gets $fp] - ksize mtime
	  puts "D $dname $ksize $mtime"
	}
	"P *" {
          puts $line
	}
        default {
          puts $line
        }
      }
      } on error err {
        puts stderr "Error: $err"
        puts stderr "       line   = $line"
        puts stderr "       dbfile = $dbfile"
        break
      }

    }
    close $fp

    return
}

proc ${NS}::find {dbfile args} {
    array set kargs {
      -type ""
      -all  0
      -tail 0
      -size 0
      -step 0
      -name ""
      -path ""
      -maxdepth 0
      -mindepth 0
      -yield 0
      -yieldto ""
    }
    array set kargs $args

    package require cardfile

    CardFile create diskcard

    diskcard open $dbfile

    if {$kargs(-yield)} {
      set kargs(-yieldto) [yield]
    }

    array set card [list -frcode 1 -dir "" -mtime-incr 1 atime 0]

    while {[diskcard next_card card]} {

          set match 1

          while 1 {
            if { $kargs(-maxdepth)>0 && $card(-depth) > $kargs(-maxdepth) } {
              set match 0
              break
            }
            if { $kargs(-mindepth)>0 && $card(-depth) < $kargs(-maxdepth) } {
              set match 0
              break
            }
            if { $card(-type) in "% ."} {
              set match 0
              break
            }

            if { !$kargs(-step) && $card(-type) in "R P"} {
              set match 0
              break
            }

            if {!($kargs(-size)<=0 || $card(ksize)>=$kargs(-size))} {
              set match 0
              break
            }
            if {!($kargs(-type) eq "" || $card(-type) in $kargs(-type))} {
              set match 0
              break
            }
            if {!($kargs(-name) eq "" || [string match $kargs(-name) $card(name)])} {
              set match 0
              break
            }
            if {!($kargs(-path) eq "" || [string match $kargs(-path) [file join $card(-dir) $card(name)]])} {
              set match 0
              break
            }
            if { !$kargs(-all) && $card(-type) eq "X" } {
              set match 0
              break
            }

            break
          }

          if {!$match} continue

          if {$kargs(-yieldto) ne ""} {
            yieldto $kargs(-yieldto) $card(-type) $card(name) $card(ksize) $card(mtime) $card(atime)
          } elseif {$kargs(-yield)} {
            yield [list $card(-type) $card(name) $card(ksize) $card(mtime) $card(atime)]
          } else {
            if {$kargs(-tail)} {
	      puts [list $card(-type) $card(name) $card(ksize) $card(mtime) $card(atime)]
            } else {
              set fpath [file join $card(-dir) $card(name)]
	      puts [list $card(-type) $fpath $card(ksize) $card(mtime) $card(atime)]
            }
          }
    }

    diskcard close
    return
}


proc ${NS}::dirstat {act args} {
  if {$act eq "new"} {
    set dirstat {
	depth 0 line 0
	stat {ksize 0 mtime 0 readable 1}
	file "" dir "" xfile "" ztime 0
    }
    foreach {name value} $args {
      dict set dirstat $name $value
    }
    return $dirstat
  }
}

proc ${NS}::update_dbfile {dbfile args} {

    set outfile $dbfile.work

    count::reset

    set context ""
    set cwd     ""
    set dirpath ""
    set dirstat_conf [dict create dirs {}]

    log open $outfile.log

    set force_update [expr {"-force" in $args}]

    log "debug: args = $args"

    if {$force_update} {
      unlock $dbfile
    } else {
      if {[file exist $dbfile]} {
        set update_elapse [expr {[clock seconds] - [file mtime $dbfile]}]
        if {$update_elapse < 60*30} {
          log close
          return
        }
      }
    }

    if {![lock $dbfile]} {
      log "lock $dbfile fail. skip."
      log close
      return
    }

    set dirstack [list]

    set dirs_include [list]
    set dirs_exclude [list]

    set idx [lsearch $args "-conf"]
    if {$idx>=0} {
      puts "set dirstat_conf dict merge $dirstat_conf [lindex $args $idx+1]"
      set dirstat_conf [dict merge $dirstat_conf [lindex $args $idx+1]]
    }

    set idx [lsearch $args "-include"]
    if {$idx>=0} {
      lappend dirs_include {*}[lindex $args $idx+1]
    }

    set idx [lsearch $args "-exclude"]
    if {$idx>=0} {
      lappend dirs_exclude {*}[lindex $args $idx+1]
    }

    # set fout [file temp outfile $dbfile]
    # puts "outfile = $outfile"

    set fout [open $outfile "wb"]
    chan configure $fout -buffersize [expr 4096*16]  ;# 64 KB

    set now [clock seconds]
    chan puts $fout "% datetime = [clock format $now -format {%Y-%m-%dT%H:%M:%S}]"
    chan puts $fout "% frcode = 1"
    chan puts $fout "% mtime_incr = 1"

    array set config {
      "frcode"     0
      "mtime_incr" 0
    }

    set top_dirs [list]

    if {![file exist $dbfile]} {
      set fp [open "/dev/null"]
    } else {
      set fp [open $dbfile]
      chan configure $fp -buffersize [expr 4096*16]  ;# 64 KB
      log "reading $dbfile"
    }


    set depth -1
    set lineno 0
    while {[gets $fp line]>=0} {
      incr lineno
      switch -glob -- $line {
	"#*" {
           set context ""
	   continue
	}
	"%*" {
           set context ""
           switch -- [lindex $line 1] {
             "root" {
               set cwd [lindex $line end]
             }
             "frcode" {
               set config(frcode) 1
             }
             "mtime_incr" {
               set config(mtime_incr) 1
             }
           }
	   continue
	}
	"R *" {
	  set dir [string range $line 2 end]

          frcode::prefix [file tail $dir]

	  lassign [gets $fp] - ksize mtime ztime_diff
          incr lineno

          if {$ztime_diff eq ""} {
            set ztime_diff 0
          }

          set dir_mtime $mtime
          set dir_ztime [expr {$mtime+$ztime_diff}]

	  incr depth
          set dirpath [file join $dirpath $dir]
          set context "R"

          if {$depth==0} {
            lappend top_dirs $dirpath
            chan puts $fout "% [diskit::statvfs $dirpath]"
          }

          set p_dirstat [markstack::cget dirstat]
          markstack::push $dir {}

          set dirstat_cache [dirstat new line $lineno depth $depth ztime $dir_ztime]
	  dict set dirstat_cache stat ksize $ksize
	  dict set dirstat_cache stat mtime $dir_mtime
	  dict set dirstat_cache pdirstat $p_dirstat
	}
	"P *" {
          if {$context eq "R"} {
            incr count_dirstat
	    set dirstat [update_dirstat $dirpath $dirstat_cache]
            if { ![markstack::has skip] } {
              set offset [print_dirstat $fout $dirpath $dirstat]
              markstack::cset offset $offset
              markstack::cset dirstat $dirstat
            }
          }

          set context "P"

	  # set dname [string range $line 2 end]
	  lassign [gets $fp] - offset
          incr lineno

          incr depth -1
          set dirpath [file dir $dirpath]


          if { ![markstack::has skip] } {
            set offset_diff [expr {[chan tell $fout] - [markstack::cget offset]}]
            chan puts $fout [format "P %d" $offset_diff]
            chan puts $fout "*"
          } else {
            # do not print
          }

          markstack::pop

	}
	"F *" {
          if {$config(frcode)} {
            set idx [tcl_endOfWord $line 2]
            set prefix_diff [string range $line 2 $idx-1]
            set prefix_tail [string range $line $idx+1 end]
            set fname [frcode::prefix_append $prefix_diff $prefix_tail]
          } else {
	    set fname [string range $line 2 end]
          }

	  lassign [gets $fp] - ksize mtime atime size_kb
          incr lineno

          if {$config(mtime_incr)} {
            set mtime [expr {$dir_mtime+$mtime}]
            set atime [expr {$mtime+$atime}]
          }

	  dict set dirstat_cache file $fname "ksize $ksize size_kb $size_kb mtime $mtime atime $atime"
	}
        "G*" -
        "X*" {
          # for a group of file, e.g. small files.
	  set fname [string range $line 2 end]
	  lassign [gets $fp] - count ksize mtime atime size_kb

          if {$config(mtime_incr)} {
            set mtime [expr {$dir_mtime+$mtime}]
            set atime [expr {$mtime+$atime}]
          }

	  dict set dirstat_cache xfile $fname "ksize $ksize size_kb $size_kb mtime $mtime atime $atime count $count"
        }
	"D *" {
          if {$config(frcode)} {
            set idx [tcl_endOfWord $line 2]
            set prefix_diff [string range $line 2 $idx-1]
            set prefix_tail [string range $line $idx+1 end]
            set dname [frcode::prefix_append $prefix_diff $prefix_tail]
          } else {
	    set dname [string range $line 2 end]
          }

	  lassign [gets $fp] - ksize mtime
          incr lineno

          if {$config(mtime_incr)} {
            set mtime [expr {$dir_mtime+$mtime}]
          }

	  dict set dirstat_cache dir $dname "ksize $ksize mtime $mtime"
	}
        ".*" -
	"" {
          if {$context eq "R"} {
            incr count_dirstat

	    set dirstat [update_dirstat $dirpath $dirstat_cache]

            if { ![markstack::has skip] } {
              set offset [print_dirstat $fout $dirpath $dirstat]
              markstack::cset offset $offset
              markstack::cset dirstat $dirstat
            } else {
              log "- R $dirpath"
            }
          }
          set context ""
	}
        "S" {
          # for statistic
        }
        default {
          # TODO
        }
      }

    }
    close $fp

    chan puts $fout "% datetime = [clock format $now -format {%Y-%m-%dT%H:%M:%S}]"

    set idx [lsearch $args "-dir"]
    if {$idx>=0} {
      set dirpath [lindex $args $idx+1]
    }

    if {$dirpath ne "" && $dirpath ni $top_dirs} {
      write_dirstat $fout $dirpath
      chan puts $fout "% datetime = [clock format $now -format {%Y-%m-%dT%H:%M:%S}]"
    }

    foreach dirpath [dict get $dirstat_conf dirs] {
      set prefix [string index $dirpath 0]
      if {$prefix eq "-" || $prefix eq "+"} {
        set dirpath [string range $dirpath 1 end]
      }

      if {$dirpath in $top_dirs} continue

      write_dirstat $fout $dirpath
      chan puts $fout "% datetime = [clock format $now -format {%Y-%m-%dT%H:%M:%S}]"
    }


    chan puts $fout "% elapse = [expr {[clock seconds] - $now}]"
    # chan puts $fout "% [diskit::statvfs $dirpath]"
    chan puts $fout "% file_ksize    = [count::value file_ksize]"
    chan puts $fout "% count_file    = [count::value file_count]"
    chan puts $fout "% count_dir     = [count::value dir_count]"
    chan puts $fout "% count_statf   = [count::value count_fstat]"
    chan puts $fout "% count_readdir = [count::value count_readdir]"

    close $fout

    unlock $dbfile

    if {"-debug" ni $args} {
      # TODO: add catch ...
      if {[file exist $dbfile]} {
        file rename -force $dbfile $dbfile.old
      }
      file rename -force $outfile $dbfile
    }

    log close
    return
}

# TODO: pass in a dirstat_cache
# proc dirstat_readdir {dirpath dirstat_cache {statvar ""}} {}
proc ${NS}::readdir {dirpath {statvar ""}} {

  if {![file exist $dirpath]} {
    return ""
  }

  set dirstat [dirstat new]

  try {
    count::incr count_readdir 1
    # log "readdir -stat $dirpath"
    set dir_entries ""
    set dir_entries [diskit::readdir -stat $dirpath]
    set dir_entries [lsort -stride 2 -index 0 $dir_entries]
  } on error err {
    # puts "..."
    # return $dirstat
    # TODO: check not exist || permission denied
    dict set dirstat stat readable 0
  }

  dict set dirstat ztime [clock seconds]

  try {
    if {$statvar ne ""} {
      upvar $statvar dstat
      if {[array size dstat]==0} {
        file lstat $dirpath dstat
      }
    } else {
      file lstat $dirpath dstat
    }

    set ksize      [expr {(max(0, $dstat(size)-1)>>10) + 1}]
    set mtime      [expr {max($dstat(mtime),$dstat(ctime))}]
    dict set dirstat stat "ksize" $ksize
    dict set dirstat stat "mtime" $mtime
  } on error err {
    dict set dirstat stat ""
  }

  # return if do dstat only

  foreach {fname fstat} $dir_entries {
    set ftype [dict get $fstat type]
    switch -- $ftype {
      "file" {
        set size       [dict get $fstat size]
        set size_kb    [expr {(max(0, $size-1)>>10) + 1}]
        set ksize      [dict get $fstat ksize]
        set mtime      [dict get $fstat mtime]
        set atime      [dict get $fstat atime]
        dict set dirstat file $fname [list size $size size_kb $size_kb ksize $ksize mtime $mtime atime $atime]
      }
      "dir" {
        set size       [dict get $fstat size]
        set size_kb    [expr {(max(0, $size-1)>>10) + 1}]
        set ksize      [dict get $fstat ksize]
        set mtime      [dict get $fstat mtime]
        dict set dirstat dir $fname [list size $size ksize $ksize mtime $mtime]
      }
      "link" {
      }
      "" {
        log "Warn: unknown file [file join $dirpath $fname]"
      }
      "xfile" {
        dict set dirstat xfile $fname ""
      }
    } ;# end switch
  } ;# end foreach

  return $dirstat
}

# TODO:
proc ${NS}::globdir {dirpath} {
  foreach path [lsort [concat [glob -nocomplain -dir $dirpath *] [glob -nocomplain -dir $dirpath -type hidden *]]] {
    set fname [file tail $path]

    if {$fname eq "." || $fname eq ".."} continue

    try {
      file lstat $path stat
      set ftype $stat(type)
    } on error err {
      set ftype "fail"
    }


    switch -- $ftype {
      "file" {
        set ksize      [expr {(max(0, $stat(size)-1)>>10) + 1}]
        set mtime      [expr {max($stat(mtime),$stat(ctime))}]
        set atime      $stat(atime)
        dict set dirstat file $fname [list ksize $ksize mtime $mtime atime $atime]
      }
      "directory" {
        set ksize      [expr {(max(0, $stat(size)-1)>>10) + 1}]
        set mtime      [expr {max($stat(mtime),$stat(ctime))}]
        dict set dirstat dir $fname [list ksize $ksize mtime $mtime]
      }
      "xfile" {
        dict set dirstat xfile $fname ""
      }
    }
  }
}

proc ${NS}::check_dirstat {dirstat_cache dirpath &reason} {
  upvar ${&reason} reason
  set reason ""

  set do_update 0

  set depth     [dict get $dirstat_cache depth]
  set dir_mtime [dict get $dirstat_cache stat mtime]
  set dir_ztime [dict get $dirstat_cache ztime ]

  array set dirpath_stat ""

  if { $dir_mtime==0 } {
    # if dir mtime==0, the dir is not visisted
    set do_update 9
    set reason "mtime unset"
    return $do_update
  } elseif {$depth <= 5} {
    # Always check top N level of directories
    # TODO: make '4' a config
    try {
      file lstat $dirpath dirpath_stat
      if {max($dirpath_stat(mtime),$dirpath_stat(ctime)) != $dir_mtime} {
	set do_update 1
        set reason "mtime diff"
        return $do_update
      }
    } trap {POSIX ENOENT} {} {
      # ENOENT = Not Exist
      set do_update -1
      set reason "not exist"
      return $do_update
    }
  }

  # Check dir existance is relative high cost.
  # We can defer this check, unless
  #   1. see "big" files which is missing.
  #   2. mtime decay reach a limit.
  if {0} {
    set is_dir [file isdir $dirpath]
    if {!$is_dir} {
      set do_update -1
      return $do_update
    }
  }

  set sum_ksize 0
  set max_mtime 0

  # If we see "big" file in this dir, check its existance.
  # If it was deleted, try to update or skip current dir, depending on whether current dir exist.
  # "big" = file size > 100M ~= 128 = 2^7
  set ksize_limit [expr {1024*100}]
  dict for {fname fstat_cache} [dict get $dirstat_cache file] {
    set ksize      [dict get $fstat_cache ksize]
    set mtime      [dict get $fstat_cache mtime]
    set atime      [dict get $fstat_cache atime]

    incr sum_ksize $ksize
    incr max_mtime [expr {max($max_mtime, $mtime)}]

    # TODO: e
    if { $ksize > $ksize_limit } {
      count::incr count_fstat 1
      try {
	file lstat [file join $dirpath $fname] fstat
	#TODO: dict set $dirstat file $fname "..."
      } trap {POSIX ENOENT} {} {
	# ENOENT = Not Exist
        set is_dir [file isdir $dirpath]
        if {$is_dir} {
          set reason "big file missing $fname"
	  set do_update 1
          # TODO: It's common to see big file, so decide update dir only
          # because a signle big file is not smart.
	  # return $do_update
        } else {
          set reason "big file dir missing"
	  set do_update -1
	  return $do_update
        }
      } on error {err erropts} {
	#
      }
    }
  }

  # TODO: check xfile
  # dict for {fname fstat_cache} [dict get $dirstat_cache xfile] {
  # }


  if {$do_update < 0} {
    return $do_update
  }

  # Check mtime Exponential Decay

  # gnuplot:  ratio_ztime = 0.03 , ratio_mtime = 0.04
  # plot  1-exp(-ratio_mtime*x) with points lc "blue",  1-exp(-ratio_mtime*x*60*exp(-12*ratio_ztime)), 1-exp(-ratio_mtime*x*60*exp(-48*ratio_ztime)), 1-exp(-ratio_mtime*x*60*exp(-72*ratio_ztime)), 1-exp(-ratio_mtime*x*60*exp(-24*4*ratio_ztime))

  if {0} {
    # chance of file changed since ztime
    set ratio_mtime 0.05  ;# 0.04
    set ratio_ztime 0.08  ;# 0.03
    set p_threshold 0.8
    set now [clock seconds]
    set ratio_mtime [expr {$ratio_mtime*exp(-($dir_ztime-$dir_mtime)/3600*$ratio_ztime)}]
    set p [expr {1-exp(-($now - $dir_ztime)/60*$ratio_mtime)}]
    #set t [expr {-log(1-$p_threshold)/$ratio_mtime}]

    set ztime_diff [expr {($now-$dir_ztime)}]
    if {$p > $p_threshold} {
      # > 30 minutes. TODO: make this hyper parameter
      if { $ztime_diff > 60*30 } {
	set do_update 1
	return $do_update
      }
    } else {
      # > 24 hours. TODO: make this hyper parameter
      if { $ztime_diff > 3600*24 } {
	set do_update 1
	return $do_update
      }
    }
  }

  # 1-exp(-x*0.02*3*exp(-100*0.01))

  set ratio_ztime_hour 0.02
  set ztime_diff_max   [expr {3600*24*1}]  ;# 24 hours
  set ztime_diff_min   [expr {60*30}]      ;# 30 minutes


  if {$sum_ksize < (1024*10)} {
    # set do_update 0
    set ratio_ztime_hour 0.04
    set ztime_diff_max   [expr {3600*24*2}]  ;# 48 hours
    set ztime_diff_min   [expr {3600*4}]     ;#  4 hours
  }

  set p [expr {1-exp(-$ratio_ztime_hour*($dir_ztime - $dir_mtime)/3600)}]
  set ztime_diff [expr {max($p*$ztime_diff_max, $ztime_diff_min)}]

  set now [clock seconds]
  if {($now-$dir_ztime) > $ztime_diff} {
    set reason "mtime decay"
    set do_update 1
  }

  return $do_update
}

proc ${NS}::update_dirstat {dirpath dirstat_cache} {

  if { [markstack::has skip] } {
    return $dirstat_cache
  }

  set depth [dict get $dirstat_cache depth]

  if {$depth > 0 && ![dict exist $dirstat_cache pdirstat dir [file tail $dirpath]]} {
    markstack::mark "skip"
    return $dirstat_cache
  }


  set do_update [check_dirstat $dirstat_cache $dirpath reason]

  if {$do_update < 0} {
    log "skip $dirpath # $reason"

    markstack::mark "skip"
    return $dirstat_cache
  } elseif { $do_update>0 } {
    # XXX: readdir

    log "readdir -stat $dirpath # $reason"
    set dirstat [readdir $dirpath dirpath_stat]

    if {$dirstat eq ""} {
      log "debug: mark skip $dirpath after readdir"
      markstack::mark "skip"
      return $dirstat_cache
    }

    dict set dirstat depth $depth
  } else {
    # log "reuse $dirpath # $reason"
    set dirstat $dirstat_cache
  }

  dict for {dname dstat_cache} [dict get $dirstat dir] {
    if { ![dict exist $dirstat_cache dir $dname] } {
      dict set dirstat dir $dname isnew 1
    } else {
      dict set dirstat dir $dname isnew 0
    }
  }

  return $dirstat
}

proc ${NS}::print_dirstat_file {fout dirstat_file} {
  upvar sum sum
  upvar dir_mtime dir_mtime
  upvar dir_depth dir_depth

  dict for {fname fstat_cache} $dirstat_file {

    if {[dict exist $fstat_cache mtime]} {
      # TODO
      set ksize      [dict get $fstat_cache ksize]
      set size_kb    [dict get $fstat_cache size_kb]
      set mtime      [dict get $fstat_cache mtime]
      set atime      [dict get $fstat_cache atime]
      incr sum(file_ksize) $ksize
      set  sum(file_mtime) [expr {max($sum(file_mtime), $mtime)}]
      incr sum(file_count) 1
    }

    # TODO:
    set ksize [dict get $fstat_cache ksize]
    if {$dir_depth > 8 && $ksize ne "" && $ksize<100} {
      # continue
      set  size_kb    [dict get $fstat_cache size_kb]
      set  mtime      [dict get $fstat_cache mtime]

      incr sum(sfile_ksize)   $ksize
      incr sum(sfile_size_kb) $size_kb
      incr sum(sfile_count) 1
      set  sum(sfile_mtime) [expr {max($sum(sfile_mtime), $mtime)}]

      # XXX: skip print small files, sum them into a "xfile" group
      continue
    }

    lassign [frcode::prefix_diff $fname] prefix_diff prefix_tail
    chan puts $fout [format "F %d %s" $prefix_diff $prefix_tail]

    # puts [format "F %s" $fname]
    if {[dict exist $fstat_cache ztime]} {
      # set ztime_diff [expr {$ztime-$mtime}]
      # chan puts $fout [format "T %d" $ztime_diff]
    }

    if {[dict exist $fstat_cache mtime]} {
      # TODO
      set ksize      [dict get $fstat_cache ksize]
      set size_kb    [dict get $fstat_cache size_kb]
      set mtime      [dict get $fstat_cache mtime]
      set atime      [dict get $fstat_cache atime]

      # incr sum(file_ksize) $ksize
      # set  sum(file_mtime) [expr {max($sum(file_mtime), $mtime)}]
      # incr sum(file_count) 1

      chan puts $fout [format "* %d %d %d %d" $ksize [expr {$mtime-$dir_mtime}] [expr {$atime-$mtime}] $size_kb]
    } else {
      chan puts $fout [format "*"]
      incr sum(xfile_count) 1
    }
  }
}

proc ${NS}::print_dirstat_dir {fout dirstat_dir} {
  upvar dir_mtime dir_mtime

  dict for {dname dstat_cache} $dirstat_dir {
    # TODO: this is needed if we scan new subdir
    # if {0 && $dir_depth > 8} {
    #   continue
    # }

    lassign [frcode::prefix_diff $dname] prefix_diff prefix_tail
    chan puts $fout [format "D %d %s" $prefix_diff $prefix_tail]

    count::incr dir_count 1

    if {[dict exist $dstat_cache mtime]} {
      # TODO
      set ksize [dict get $dstat_cache ksize]
      set mtime [dict get $dstat_cache mtime]
      chan puts $fout [format "* %d %d" $ksize [expr {$mtime-$dir_mtime}]]
    } else {
      chan puts $fout [format "*"]
    }
  }
}

proc ${NS}::print_dirstat_xfile {fout dirstat_xfile} {
  upvar sum sum
  upvar dir_mtime dir_mtime

  if {[dict size $dirstat_xfile]>0} {
    set fname "s"
    set ksize      [dict get $dirstat_xfile $fname ksize ]
    set size_kb    [dict get $dirstat_xfile $fname size_kb ]
    set mtime      [dict get $dirstat_xfile $fname mtime ]
    set atime      [dict get $dirstat_xfile $fname atime ]
    set count      [dict get $dirstat_xfile $fname count ]

    chan puts $fout [format "X %s" $fname]
    chan puts $fout [format "* %d %d %d %d %d" $count $ksize [expr {$mtime-$dir_mtime}] [expr {$atime-$mtime}] $size_kb]
  } elseif {$sum(sfile_count) > 0} {
    set fname "s"
    set mtime    $sum(sfile_mtime)
    set ksize    $sum(sfile_ksize)
    set size_kb  $sum(sfile_size_kb)
    set atime    0
    set count    $sum(sfile_count)

    chan puts $fout [format "X %s" $fname]
    chan puts $fout [format "* %d %d %d %d %d" $count $ksize [expr {$mtime-$dir_mtime}] [expr {$atime-$mtime}] $size_kb]
  }
}

proc ${NS}::print_dirstat_newdir {fout dirstat dirpath dir_depth} {

  dict for {dname dstat_cache} [dict get $dirstat dir] {
    if {[dict get $dstat_cache isnew]} {
      log "+ D $dirpath/$dname"

      # XXX: TODO: use stack::peak to replace pdirstat
      # Need push sub_dirstat

      set sub_dirstat [dirstat new depth $dir_depth pdirstat $dirstat]
      set sub_dirpath [file join $dirpath $dname]
      markstack::push $dname {}
      set sub_dirstat [update_dirstat      $sub_dirpath $sub_dirstat]
      # markstack::cset offset $offset
      markstack::cset dirstat $dirstat

      set sub_offset  [print_dirstat $fout $sub_dirpath $sub_dirstat]
      chan puts $fout [format "P %d" [expr {[chan tell $fout] - $sub_offset}]]
      chan puts $fout "*"
      markstack::pop
    }
  }
}

proc ${NS}::print_dirstat {fout dirpath dirstat} {

  set dir_depth [dict get $dirstat depth]
  set dir_ksize [dict get $dirstat stat ksize]
  set dir_mtime [dict get $dirstat stat mtime]
  set dir_read  [dict get $dirstat stat readable]
  set dir_ztime [dict get $dirstat ztime]

  set offset [chan tell $fout]

  if {$dir_depth == 0} {
    chan puts $fout [format "R %s" $dirpath]
  } else {
    chan puts $fout [format "R %s" [file tail $dirpath]]
  }


  if {$dir_read} {
    # chan puts $fout [format "+ %d %d %d" $dir_ksize $dir_mtime [expr {$dir_ztime-$dir_mtime}]]
    chan puts $fout [format "* %d %d %d" $dir_ksize $dir_mtime [expr {$dir_ztime-$dir_mtime}]]
  } else {
    chan puts $fout [format "? %d %d %d" $dir_ksize $dir_mtime [expr {$dir_ztime-$dir_mtime}]]
  }

  frcode::prefix [file tail $dirpath]

  array set sum "file_ksize 0 file_mtime 0 file_count 0 file_size_kb 0"
  array set sum "sfile_ksize 0 sfile_mtime 0 sfile_count 0 sfile_size_kb 0"

  print_dirstat_file  $fout [dict get $dirstat file]
  print_dirstat_xfile $fout [dict get $dirstat xfile]
  print_dirstat_dir   $fout [dict get $dirstat dir]

  if {$sum(file_count) > 0} {
    chan puts $fout [format ". %d %d %d" $sum(file_count) $sum(file_ksize) $sum(file_mtime)]
  } else {
    chan puts $fout "."
  }

  count::incr file_ksize $sum(file_ksize)
  count::incr file_count $sum(file_count)


  incr dir_depth
  print_dirstat_newdir $fout $dirstat $dirpath $dir_depth

  return $offset
}

proc ${NS}::write_dirstat {fout dirpath {depth 0}} {

  markstack::push $dirpath {}

  set dirstat [dict create depth $depth file "" dir "" stat ""]
  set dirstat [update_dirstat $dirpath $dirstat]

  # markstack::cset offset $offset
  markstack::cset dirstat $dirstat

  set offset  [print_dirstat $fout $dirpath $dirstat]
  chan puts $fout [format "P %d" [expr {[chan tell $fout] - $offset}]]
  chan puts $fout "*"
  markstack::pop

  return
}

proc ${NS}::write_dbfile {dirpath outfile} {
  set fout [open $outfile "wb"]
  write_dirstat $fout $dirpath
  close $fout

  return
}
