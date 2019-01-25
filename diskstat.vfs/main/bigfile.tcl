
proc lstack {args} {
}

if {0} {
    array set kargs {
      -decode 0
      -sort   0
      -size   300000
      %       ""
    }

    set arg_next  0
    set arg_skip 0
    foreach arg $::argv {
      incr arg_next
      if {$arg_skip>0} {
	incr arg_skip -1
	continue
      }

      switch -- $arg {
	"-decode" { set ::kargs(-decode) 1 }
	"-sort"   { set ::kargs(-sort)   1 }
	"-size"   {
	  set ::kargs(-size) [lindex $::argv $arg_next]
	  incr arg_skip 1
	}
	default {
	  lappend ::kargs(%) $arg
	}
      }
    }

    lassign $::kargs(%) dbfile outfile
}

set dbfile  $::kargs(-dbfile)
set outfile $::kargs(-outfile)

# if {$outfile ne ""} {
#
# }

set dirstat_exec $::argv0

if {$::kargs(-decode)} {
  set fpipe [open "| $dirstat_exec decode $dbfile 2>@ stderr" "r"]
} else {
  set fpipe [open $dbfile "r"]
}

if {$outfile eq ""} {
  # set fout  [open "| sort -nrk 2 >@ stdout" "w"]
  set fout  stdout
} else {
  # TODO:
  set outfile $dbfile.bigfile
  set fout  [open $outfile.work "w"]
}


set fout_keep $fout
if {$::kargs(-sort)} {
  set fout  [open "| sort -nrk 2 >@ $fout" "w"]
} else {
  set fout  $fout
}

set dir_stack [list]

set current_dir ""
set dir_marks   ""
set current_marks [dict create]
set depth 0

proc dir_stack {act {value ""}} {
  global dir_stack
  global dir_stack_top

  switch -- $act {
    "init" {
      set dir_stack    [list]
      set dir_stack_top 0
    }
    "top" {
      return $dir_stack_top
    }
    "size" {
      return [llength $dir_stack]
    }
    "push" {
      incr dir_stack_top
      if {$dir_stack_top > [llength $dir_stack]} {
        lappend dir_stack $value
      } else {
        lset dir_stack $dir_stack_top-1 $value
      }
      return
    }
    "pop" {
      incr dir_stack_top -1
      set value [lindex $dir_stack $dir_stack_top]
      return $value
    }
    "peek" {
      set value [lindex $dir_stack $dir_stack_top-1]
      return $value
    }
  }
  return
}

while {[gets $fpipe line]>=0} {
  switch -glob -- $line {
    "R*" {
      lassign $line - dname
      set current_dir [file join $current_dir $dname]

      dir_stack push $dir_marks

      set dir_marks [dict create]
    }
    "F*" {
      lassign $line - fname ksize mtime atime

      set depth [dir_stack top]
      set n_64mb [expr {$ksize>>14}]   ;# 16M
      dict incr count_sum count:fsize:$n_64mb
      dict incr count_sum sum:fsize:$n_64mb $ksize
      dict incr count_sum count:fdepth:$depth
      dict incr count_sum sum:fdepth:$depth   $ksize

      switch -- $fname {
        "KEEP" {
          # puts "# mark KEEP $current_dir $fname"
          dict incr current_marks KEEP 1
          dict set dir_marks KEEP 1
        }
      }

      if {$ksize>$::kargs(-size)} {
        puts $fout [list "F" $ksize $mtime $atime [dict keys $current_marks] [file join $current_dir $fname]]
      }
    }
    "G*" {
      lassign $line - fname fcount ksize mtime atime

      if {$ksize>$::kargs(-size)} {
        puts $fout [list "G" $ksize $mtime $atime [dict keys $current_marks] [file join $current_dir "*"]]
      }
    }
    "D*" {
      lassign $line - dname ksize mtime

      set depth [dir_stack top]
      set n_64mb [expr {$ksize>>9}]    ;# 512K
      dict incr count_sum count:dsize:$n_64mb
      dict incr count_sum sum:dsize:$n_64mb   $ksize
      dict incr count_sum count:ddepth:$depth
      dict incr count_sum sum:ddepth:$depth   $ksize
    }
    "P*" {
      set current_dir [file dir $current_dir]

      dict for {mark -} $dir_marks {
        # puts "# unset $mark"
        lassign [dict incr current_marks $mark -1] - mark_count
        if {$mark_count==0} {
          dict unset current_marks $mark
        }
      }

      set dir_marks [dir_stack pop]
    }
  }
}
close $fpipe

if {$::kargs(-sort)} {
  close $fout
  set fout $fout_keep
}

puts $fout "#%data file_ksize {"
foreach key [dict keys $count_sum count:fsize:*] {
  lassign [split $key ":"] - - subkey
  puts $fout "# $subkey [dict get $count_sum count:fsize:$subkey] [dict get $count_sum sum:fsize:$subkey]"
}
puts $fout "#}"

puts $fout "#%data dir_ksize {"
foreach key [dict keys $count_sum count:dsize:*] {
  lassign [split $key ":"] - - subkey
  puts $fout "# $subkey [dict get $count_sum count:dsize:$subkey] [dict get $count_sum sum:dsize:$subkey]"
}
puts $fout "#}"

puts $fout "#%data file_depth {"
foreach key [dict keys $count_sum count:fdepth:*] {
  lassign [split $key ":"] - - subkey
  puts $fout "# $subkey [dict get $count_sum count:fdepth:$subkey] [dict get $count_sum sum:fdepth:$subkey]"
}
puts $fout "#}"

puts $fout "#%data dir_depth {"
foreach key [dict keys $count_sum count:ddepth:*] {
  lassign [split $key ":"] - - subkey
  puts $fout "# $subkey [dict get $count_sum count:ddepth:$subkey] [dict get $count_sum sum:ddepth:$subkey]"
}
puts $fout "#}"


close $fout

if {$outfile ne ""} {
  if [file exist $outfile] {
    file rename -force $outfile $outfile.old
  }

  file rename -force $outfile.work $outfile
}
