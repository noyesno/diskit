# vim:set syntax=tcl sw=2 :#

package provide frcode 0.1

namespace eval frcode {
    variable prefix ""

    variable prev 
    array set prev {string "" prefix_length 0}

    proc prefix {args} {
      variable prev

      if {[llength $args]==0} {
        return $prev(string)
      } else {
        set prev(string)        [lindex $args 0]
        set prev(prefix_length) 0
      }
    }

    proc prefix_diff {name} {
      variable prev

      set prev_string $prev(string)
      set prev_length [string length $prev_string]

      for {set n $prev_length} { $n > 0 } { incr n -1 } {
	if { [string compare -length $n $prev_string $name] == 0 } {
	  break
	}
      }

      # 1 .. n
      # -(1-n) .. 0
      set prefix_length $n
      set prefix_tail   [string range $name $prefix_length end]
      # set prefix_diff   [expr {$prev_size - $prefix_length}]
      set prefix_diff   [expr {$prefix_length - $prev(prefix_length)}] 


      set prev(string)  $name
      set prev(prefix_length)  $prefix_length

      return [list $prefix_diff $prefix_tail]
    }

    proc prefix_append {prefix_diff prefix_tail} {
      variable prev

      set prefix_length [expr {$prev(prefix_length) + $prefix_diff}]

      set result [string range $prev(string) 0 $prefix_length-1]
      append result $prefix_tail

      set prev(string) $result
      set prev(prefix_length) $prefix_length

      return $result
    }
}

if {[file normalize $::argv0] ne [file normalize [info script]]} {
  return
}

puts ""
puts "------ encode ------"

set lines {
   /usr/src
   /usr/src/cmd/aardvark.c
   /usr/src/cmd/armadillo.c
   /usr/tmp/zoo
}

frcode::prefix ""
foreach text $lines {
  set prefix_encode [frcode::prefix_diff $text]
  lappend prefix_result $prefix_encode
  lassign $prefix_encode prefix_diff prefix_tail
  puts [format "%3d %-32s # %s" $prefix_diff $prefix_tail $text]

}

puts ""
puts "------ decode ------"

frcode::prefix ""
foreach item $prefix_result gold $lines {
  lassign $item prefix_diff prefix_tail
  set result [frcode::prefix_append $prefix_diff $prefix_tail]

  if {$result ne $gold} {
    puts "FAIL: $result != $gold"
  } else {
    puts "PASS: $result"
  }
}
puts ""

exit
