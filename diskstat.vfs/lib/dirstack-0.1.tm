# vim:set syntax=tcl sw=2: #

oo::class create DirStack {

  constructor {} {
    my variable stack
    my variable stack_top

    set stack_top 0
    set stack      [list]
  }

  method top {} {
    my variable stack_top

    return $stack_top
  }

  method size {} {
    my variable stack

    return [llength $stack]
  }

  method push {value} {
    my variable stack
    my variable stack_top

    if {$stack_top < [llength $stack]} {
       lset stack $stack_top $value
    } else {
       lappend stack $value
    }
    incr stack_top
    return
  }

  method pop {} {
    my variable stack
    my variable stack_top

    incr stack_top -1
    if {$stack_top<0} {
      error "pop on empty stack"
    }
    set value [lindex $stack $stack_top]
    return $value
  }

  method peek {} {
    my variable stack
    my variable stack_top

    set value [lindex $stack $stack_top-1]
    return $value
  }
}

return

