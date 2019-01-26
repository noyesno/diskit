
set dbfile  $::kargs(-dbfile)
set outfile $::kargs(-outfile)

package require dirstack

coroutine diskstat_next dirstat::find $dbfile -yield 1 -step 1 -tail 1
DirStack create dir_stack

set fout stdout

set current_dir ""
set dir_marks   ""
set current_marks [dict create]
set depth 0

set current_dir ""
while 1 {
  lassign [diskstat_next] type name ksize mtime atime

  if {$type eq ""} break
  switch -glob -- $type {
    "R" {
      set current_dir [file join $current_dir $name]

      dir_stack push $dir_marks

      set dir_marks [dict create]
    }
    "P" {
      set current_dir [file dir $current_dir]

      dict for {mark -} $dir_marks {
        lassign [dict incr current_marks $mark -1] - mark_count
        if {$mark_count==0} {
          dict unset current_marks $mark
        }
      }

      set dir_marks [dir_stack pop]
    }
    "F" {

      set depth [dir_stack top]
      set n_64mb [expr {$ksize>>14}]   ;# 16M
      dict incr count_sum count:fsize:$n_64mb
      dict incr count_sum sum:fsize:$n_64mb $ksize
      dict incr count_sum count:fdepth:$depth
      dict incr count_sum sum:fdepth:$depth   $ksize

      switch -- $name {
        "KEEP" {
          dict incr current_marks KEEP 1
          dict set dir_marks KEEP 1
        }
      }

      if {$ksize>$::kargs(-size)} {
        set fpath [file join $current_dir $name]
        puts $fout [list "F" $ksize $mtime $atime [dict keys $current_marks] $fpath]
      }
    }
    "G" {
      if {$ksize>$::kargs(-size)} {
        set fpath [file join $current_dir "*"]
        puts $fout [list "G" $ksize $mtime $atime [dict keys $current_marks] $fpath]
      }
    }
    "D" {
      set depth [dir_stack top]
      set n_64mb [expr {$ksize>>9}]           ;# 512K
      dict incr count_sum count:dsize:$n_64mb
      dict incr count_sum sum:dsize:$n_64mb   $ksize
      dict incr count_sum count:ddepth:$depth
      dict incr count_sum sum:ddepth:$depth   $ksize
    }
  }
}


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

exit
