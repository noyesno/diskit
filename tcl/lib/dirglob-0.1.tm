# vim:set syntax=tcl sw=2 :#

package provide dirglob 0.1
package require sqlite3

namespace eval dirglob {
  variable dbcmd ""
  variable dbmem ""

  proc init {dbfile} {
    variable dbcmd
    variable dbmem

    profile mark "proc"
    if {$dbcmd eq ""} {
      set dbcmd [format "dbcmd%d" [info cmdcount]]
      sqlite3 $dbcmd $dbfile
      $dbcmd timeout 60000 ;# default 60 seconds

      # PRAGMA journal_mode=WAL;

      $dbcmd eval {
        PRAGMA synchronous=off;

        ATTACH ':memory:' as mem;

        CREATE TABLE IF NOT EXISTS globstat (
          cmd   text PRIMARY KEY,
          ztime INTEGER DEFAULT 0,
          mtime INTEGER DEFAULT 0,
          result text
        );

        CREATE TABLE IF NOT EXISTS mem.globstat (
          cmd   text PRIMARY KEY,
          ztime INTEGER DEFAULT 0,
          mtime INTEGER DEFAULT 0,
          result text
        );

        INSERT INTO mem.globstat SELECT * FROM globstat;
      }
    }
    profile incr dirglob::init "proc"
  }
  proc flush {args} {
    variable dbcmd

    profile mark "proc"
    $dbcmd eval {
      DELETE FROM globstat;
      INSERT INTO globstat SELECT * FROM mem.globstat;
    }
    profile incr dirglob::flush "proc"
  }

  proc glob {args} {
    variable dbcmd

    set idx [lsearch $args "-dir"]
    if {$idx>=0} {
      set dir [lindex $args $idx+1]
    } else {

    }

    if [catch {
      profile mark "step"
      file stat $dir stat
      profile incr dirglob::stat "step"
    } err] {
      return ""
    }

    set mtime $stat(mtime)
    set cache_mtime   ""
    set cache_result ""


    set cmd $args
    profile mark "step"
    $dbcmd eval {
      SELECT * FROM mem.globstat WHERE cmd=$cmd LIMIT 1
    } row {
      set cache_mtime  $row(mtime)
      set cache_result $row(result)
    }
    profile incr dirglob::query "step"

    set ztime [clock seconds]

    if {$cache_mtime ne "" && $mtime==$cache_mtime} {
      set result $cache_result

      profile mark "step"
      $dbcmd eval {
        UPDATE mem.globstat SET ztime=$mtime WHERE cmd=$cmd;
      }
      profile incr dirglob::update-ztime "step"

      # profile mark "step"
      # $redis setex "dirglob $cmd" 3600 $result
      # profile incr dirglob::update-redis "step"

      return $result
    }


    set result [::glob {*}$args]  ;# Do the job here.

    profile mark "step"
    $dbcmd eval {
      UPDATE mem.globstat SET mtime=$mtime, result=$result WHERE cmd=$cmd;
      INSERT OR IGNORE into mem.globstat
         (cmd, ztime, mtime, result)
        VALUES
         ($cmd, $ztime, $mtime, $result);
    }
    profile incr dirglob::insert "step"

    return $result
  }
}

