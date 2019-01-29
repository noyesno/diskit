
set dbfile  $::kargs(-dbfile)
set outfile $::kargs(-outfile)

package require dirstack

coroutine walk_diskstat dirstat::find $dbfile -yield 1 -step 1 -tail 1

coroutine count_bigfile apply {{} {

  DirStack create dir_stack

  set current_dir ""
  set dir_marks   ""
  set current_marks [dict create]
  set depth 0

  set current_dir ""

  yield

  while 1 {
    if {0} {
      lassign [yieldto walk_diskstat count_bigfile] type name ksize mtime atime
    } else {
      lassign [walk_diskstat] type name ksize mtime atime
    }

    # lassign [diskstat_next] type name ksize mtime atime

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
	  write_bigfile [list "F" $ksize $mtime $atime [dict keys $current_marks] $fpath]
	}
      }
      "G" {
	if {$ksize>$::kargs(-size)} {
	  set fpath [file join $current_dir "*"]
	  write_bigfile [list "G" $ksize $mtime $atime [dict keys $current_marks] $fpath]
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

  write_bigfile -close
  write_bigstat $count_sum
}}


coroutine write_bigfile apply {{bigfile} {

  puts "debug: write to $bigfile.work"
  set fout [open $bigfile.work "w"]

  if {$::kargs(-sort)} {
    set fout_file $fout
    set fout  [open "| sort -nrk 2 >@ $fout" "w"]
    # chan push $fout [ExecPipeFilter new $fout "sort -nrk 2" ]
  }

  while 1 {
    set line [yield]
    if {$line eq "" || $line eq "-close"} break
    chan puts $fout $line
    # chan flush $fout
  }

  catch { chan close $fout }

  if {$::kargs(-sort)} {
    catch { chan close $fout_file }
  }

  file rename -force $bigfile.work $bigfile

}} $dbfile.bigfile



coroutine write_bigstat apply {{bigstat} {
  set count_sum [yield]

  puts "debug: write to $bigstat.work"
  set fout [open $bigstat.work "w"]

  puts $fout "%data file_ksize {"
  foreach key [dict keys $count_sum count:fsize:*] {
    lassign [split $key ":"] - - subkey
    puts $fout "  $subkey [dict get $count_sum count:fsize:$subkey] [dict get $count_sum sum:fsize:$subkey]"
  }
  puts $fout "}"

  puts $fout "%data dir_ksize {"
  foreach key [dict keys $count_sum count:dsize:*] {
    lassign [split $key ":"] - - subkey
    puts $fout "  $subkey [dict get $count_sum count:dsize:$subkey] [dict get $count_sum sum:dsize:$subkey]"
  }
  puts $fout "}"

  puts $fout "%data file_depth {"
  foreach key [dict keys $count_sum count:fdepth:*] {
    lassign [split $key ":"] - - subkey
    puts $fout "  $subkey [dict get $count_sum count:fdepth:$subkey] [dict get $count_sum sum:fdepth:$subkey]"
  }
  puts $fout "}"

  puts $fout "%data dir_depth {"
  foreach key [dict keys $count_sum count:ddepth:*] {
    lassign [split $key ":"] - - subkey
    puts $fout "  $subkey [dict get $count_sum count:ddepth:$subkey] [dict get $count_sum sum:ddepth:$subkey]"
  }
  puts $fout "}"

  chan close $fout

  file rename -force $bigstat.work $bigstat
}} $dbfile.bigstat


count_bigfile continue

exit
