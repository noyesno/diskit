
namespace eval ::lzw {
  variable buffer ""
  variable next_code "\x0"
  variable next_code "A"
  variable sync_char "+"

  proc encode {text} {
    variable buffer
    variable next_code

    set result ""

    set prefix ""
    set text "$text\0"
    for {set i 0 ; set n [string length $text]} {$i<$n} {incr i} {
      set char [string index $text $i]
      if {[dict exist $buffer "$prefix$char"]} {
        append prefix $char
        continue
      }

      if {![dict exist $buffer $prefix]} {
        dict set buffer $prefix ""
      }

      set code [dict get $buffer $prefix]

      if {$code ne ""} {
        # append result "\x01" $code $char
        scan $code "%c" code_value
        append result "\$($code_value)"
        incr i -1
      } else {
        append result $prefix
        incr i -1
      }

      append prefix $char
      add_code $prefix
      set prefix ""
    }
    if {$prefix ne ""} { append result $prefix }

    return $result
  }

  proc add_code {prefix} {
    variable buffer
    variable next_code

      if {[string length $prefix]>2} {
        scan $next_code "%c" next_code_int
        incr next_code_int;
        if {$next_code_int > 240} {
          puts "reach 240"; exit
        }
        set next_code [format "%c" $next_code_int]
        dict set buffer $prefix $next_code
        puts "debug: \$$next_code_int = $prefix"
      } else {
        dict set buffer $prefix ""
      }
  }

  proc decode {text} {
    variable buffer
    variable next_code

    set result ""

    set prefix ""
    set text "$text\0"
    for {set i 0 ; set n [string length $text]} {$i<$n} {incr i} {
      set char [string index $text $i]

      if {$char eq $sync_char} {
        set code [string index $text $i+1] ; incr i
        append result $prefix [code2char $code]
        set prefix ""
        continue
      }

      if {[dict exist $buffer "$prefix$char"]} {
        append prefix $char
        continue
      }

      append result $prefix

      if {![dict exist $buffer $prefix]} {
        dict set buffer $prefix ""
      }

      set code [dict get $buffer $prefix]

      if {$code ne ""} {
        # append result "\x01" $code $char
        scan $code "%c" code_value
        append result "\$($code_value)"
        incr i -1
      } else {
        append result $prefix
        incr i -1
      }

      append prefix $char
      add_code $prefix
      set prefix ""
    }
    if {$prefix ne ""} { append result $prefix }

    return $result
  }
}

foreach line {
  a
  abc
  abcd
  abc1234
  abc4567
  def
  def3
  defdef3
  defdef4
} {
  set encoded [lzw::encode $line]
  puts "result = $encoded <- $line"
}


