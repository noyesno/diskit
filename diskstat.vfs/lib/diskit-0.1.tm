
# package ifneeded diskit 0.1 [list load [file join $dir libdiskit.so]]

set dir [file dir [info script]]

load [file join $dir libdiskit.so]
package provide diskit 0.1

