# vim:set syntax=tcl sw=2: #

oo::class create CardFile {

  constructor {args} {
    my variable fpath
    my variable fchan


    my schema "." -meta {} -hook {
    }

    my schema "%" -meta {} -hook {
      set line $data(.line)

      switch -- [lindex $line 1] {
	"root" {
	  set data(-dir) [lindex $line end]
	}
	"frcode" {
	  set data(-frcode) 1
	}
	"mtime_incr" {
	  set data(-mtime-incr) 1
	}
      }
    }

    my schema "R" -meta {ksize mtime ztime_diff} -hook {

      set dir $data(-title)

      frcode::prefix [file tail $dir]

      if {$data(ztime_diff) eq ""} {
	set data(ztime_diff) 0
      }

      set data(-dir-mtime) $data(mtime)
      set data(-dir-ztime) [expr {$data(mtime)+$data(ztime_diff)}]

      incr data(-depth)
      set  data(-dir) [file join $data(-dir) $dir]
      set  data(name) $dir

    }

    my schema "P" -meta {ksize mtime ztime_diff} -hook {

      set  data(-dir) [file dir $data(-dir)]
      incr data(-depth) -1

    }


    my schema "G" -meta {count ksize mtime atime size_kb} -hook {
      set title $data(-title)
      set fname [string range $title 2 end]
      set data(name) $fname

      if {$data(-mtime-incr)} {
	set data(mtime) [expr {$data(-dir-mtime)+$data(mtime)}]
	set data(atime) [expr {$data(mtime)+$data(atime)}]
      }
    }
    my schema "F" -meta {ksize mtime atime size_kb} -hook {
      set title $data(-title)

      if {$data(-frcode)} {
	set idx [tcl_endOfWord $title 0]
	set prefix_diff [string range $title 0 $idx-1]
	set prefix_tail [string range $title $idx+1 end]
	set fname [frcode::prefix_append $prefix_diff $prefix_tail]
      } else {
	set fname [string range $title 2 end]
      }
      set data(name) $fname

      if {$data(-mtime-incr)} {
	set data(mtime) [expr {$data(-dir-mtime)+$data(mtime)}]
	set data(atime) [expr {$data(mtime)+$data(atime)}]
      }
    }

    my schema "D" -meta {ksize mtime} -hook {
      set title $data(-title)

      if {$data(-frcode)} {
	set idx [tcl_endOfWord $title 0]
	set prefix_diff [string range $title 0 $idx-1]
	set prefix_tail [string range $title $idx+1 end]
	set fname [frcode::prefix_append $prefix_diff $prefix_tail]
      } else {
	set fname [string range $line 2 end]
      }
      set data(name) $fname
    }
  }


  method open {file} {
    my variable fpath
    my variable fchan

    set fpath $file

    set fchan [::open $fpath "r"]
  }

  method close {} {
    my variable fpath
    my variable fchan

    chan close $fchan
  }


  # -attrs
  method schema {card_type args} {
    my variable card_schema
    set card_schema($card_type) $args
  }

  method next_card {var} {
    my variable fchan
    my variable card_schema
    my variable lineno
    upvar $var data

    set fp $fchan


    set size [chan gets $fp line] ; incr lineno
    set data(.line)  $line

    if {$size==0} {
      return -code "empty line"
    }

    if {$size<0} {
      return 0
    }

    set type [string index $line 0]

    if {$type eq "#"} {
      set data(-type) "#"
      return 1
    }

    set data(-type)  $type
    set data(-title) [string range $line 2 end]
    set data(-lineno) $lineno

    set schema     $card_schema($type)
    set meta_names [dict get $schema -meta]

    if {[llength $meta_names]==0} {
      return 1
    }

    set next_line [gets $fp] ; incr lineno

    foreach name $meta_names value [string range $next_line 2 end] {
      set data($name) $value
    }

    if [dict exist $schema -hook] {
      ::eval [dict get $schema -hook]
    }

    return 1
  }
}

return


