

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>         /* to get disk space info */
#include <dirent.h>
#include <fcntl.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <unistd.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>
#include <math.h>

#include <tcl.h>

#include <vector>
#include <string>
#include <stddef.h>              /* offsetof */


#define MAX( a, b ) ( ( a > b) ? a : b )
#define MIN( a, b ) ( ( a < b) ? a : b )

uint64_t total_size;
long long total_block;
long total_count;

extern "C" {
  struct diskitrec {
    uint64_t bsize;
    uint64_t ksize;
    uint64_t ksize_max;
    time_t   mtime;
    time_t   atime;
    time_t   ctime;
    uint32_t fcount;
    uint32_t lcount;
    uint32_t dcount;
    uint32_t ccount;      //  child count
    uint32_t nfail;
    time_t   elapse;      //  time used to scan
    time_t   mtime_max;   //  allowed max mtime
    uint32_t level;
    uint32_t depth;       //  max level
    const char *dir;
    time_t   atime_min;
    time_t   mtime_min;
    time_t   acount;
    time_t   mcount;
  };

  struct diskstat {
    uint64_t ksize;
    uint64_t ksize_max;
    uint64_t ksize_file;
    uint64_t ksize_dir;
    time_t   time;
    time_t   mtime;
    time_t   atime;
    time_t   mtime_max;
    time_t   atime_max;
    uint32_t count_dir;
    uint32_t count_file;
    uint32_t count_link;
    uint32_t depth;       //  max level
  };
}


static Tcl_Obj *key_empty = NULL;
static Tcl_Obj *key_type  = NULL;
static Tcl_Obj *key_size  = NULL;
static Tcl_Obj *key_ksize = NULL;
static Tcl_Obj *key_mtime = NULL;
static Tcl_Obj *key_atime = NULL;


void diskit_du(int dirfd, diskitrec &drec, int inclusive);

inline void disk_du_dir(int dirfd, const char *d_name, diskitrec &drec){
  if(0 == faccessat(dirfd, d_name, R_OK, AT_SYMLINK_NOFOLLOW)){
    int sdir_fd = openat(dirfd, d_name, O_RDONLY);
    if(sdir_fd == -1){
      fprintf(stderr, "open dir %s fail\n", d_name);
      drec.nfail++;
      return;
    }
    const char *dir_keep = drec.dir;
    drec.dir = d_name;
    drec.level++;
    drec.depth = MAX(drec.depth, drec.level);
    diskit_du(sdir_fd, drec, 1);
    drec.level--;
    drec.dir = dir_keep;
    close(sdir_fd);
  } else {
    // TODO:
    // fprintf(stderr, "not readable dir %s\n", d_name);
    drec.nfail++;
  }

  return;
}

inline void disk_du_file(int dirfd, const char *d_name, diskitrec &drec){
  struct stat sb;

  int ret = fstatat(dirfd, d_name, &sb, AT_SYMLINK_NOFOLLOW);
  if (ret == -1){
    switch(errno){
      case EACCES:
        // fprintf(stderr, "stat file %s fail # %s\n", d_name, "access is denied");
        break;
      default:
        // fprintf(stderr, "stat file %s errno # %d\n", d_name, errno);
        break;
    }
    drec.nfail++;
    return;
  }

  // printf("entry file %s %d %d %d | %d\n", d->d_name, sb.st_size, sb.st_blocks, sb.st_blksize, sb.st_mtime);

  // XXX: track min time?

  drec.bsize += sb.st_size;
  drec.ksize += sb.st_blocks>>1;
  drec.ksize_max = MAX(drec.ksize_max, sb.st_blocks>>1);

  if(sb.st_mtime > drec.mtime_max) {
     fprintf(stderr, "warn: see file with mtime in future # %s/%s\n", drec.dir, d_name);
     // fprintf(stderr, "debug: mtime error file %s\n", d_name);
  } else {
     drec.mtime  = MAX(sb.st_mtime, drec.mtime);
     drec.ctime  = MAX(sb.st_ctime, drec.ctime);
     drec.atime  = MAX(sb.st_atime, drec.atime);

     if(0 || S_ISREG(sb.st_mode)){
       if (sb.st_atime > drec.atime_min) drec.acount++;
       if (sb.st_mtime > drec.mtime_min) drec.mcount++;
     }
  }

  // TODO: use -progress to control
  if (0 && drec.fcount%10000 == 0) { // XXX: use drec.fcount & 0x04ff
     fprintf(stderr, "info: fcount reach %8d\n", drec.fcount);
  }

  return;
}

void diskit_du(int dirfd, diskitrec &drec, int inclusive) {
  struct dirent *d;
  DIR *dirp = fdopendir(dirfd);

  if (dirp == NULL) {
    fprintf(stderr, "fail to open dir '%s'\n");
    return;
  }

  struct stat sb;


  if (inclusive) {
    fstat(dirfd, &sb);

    // if (0 != fstat(dirfd, &sb)) {
    // // printf("dir size = %d\n", sb.st_size);

    //   switch(errno){
    //     case EACCES:
    //       // fprintf(stderr, "stat file %s fail # %s\n", d_name, "access is denied");
    //       break;
    //     default:
    //       // fprintf(stderr, "stat file %s errno # %d\n", d_name, errno);
    //       break;
    //   }
    //   drec.nfail++;
    //   return;
    // }

    drec.dcount++;
    drec.bsize += sb.st_size;
    drec.ksize += sb.st_blocks>>1;

    if(sb.st_mtime > drec.mtime_max) {
       fprintf(stderr, "warn: see dir with mtime in future # %s/\n", drec.dir);
    } else {
      drec.mtime  = MAX(sb.st_mtime, drec.mtime);
      drec.ctime  = MAX(sb.st_ctime, drec.ctime);
      drec.atime  = MAX(sb.st_atime, drec.atime);
    }
  }

  int n_entry = 0;
  errno = 0;
  while(1){
    /* XXX: check errno to tell error */
    errno = 0;
    d = readdir(dirp);
    if(d==NULL){
      if(errno!=0){
        drec.nfail++;

        switch(errno){
          case EBADF :
            fprintf(stderr, "readdir error # %s\n", "Invalid directory stream descriptor");
            break;
          default:
            fprintf(stderr, "readdir error unknown # %d\n", errno);
        }
      }
      break;
    }

    const char *name = d->d_name;
    if (name[0]=='.' && (name[1]=='.' || name[1] == '\0')) continue;
    n_entry++;
    switch(d->d_type){
      case DT_DIR : {
        // fprintf(stderr, "entry dir %s\n", d->d_name);
        disk_du_dir(dirfd, d->d_name, drec);
        break;
      }
      case DT_LNK :
        drec.lcount++;
        disk_du_file(dirfd, d->d_name, drec);

        break;
      case DT_REG : {
        drec.fcount++;
        disk_du_file(dirfd, d->d_name, drec);

        break;
      }
      case DT_UNKNOWN : {
        fstatat(dirfd, d->d_name, &sb, AT_SYMLINK_NOFOLLOW);
        if(S_ISDIR(sb.st_mode)){
          // fprintf(stderr, "unknown entry type => dir  # mode = %o\n", sb.st_mode);
          // fprintf(stderr, "unknown entry dir %s\n", d->d_name);
          disk_du_dir(dirfd, d->d_name, drec);
        }else if(S_ISREG(sb.st_mode)){
          // fprintf(stderr, "unknown entry type => file # mode = %o\n", sb.st_mode);
          drec.fcount++;
          disk_du_file(dirfd, d->d_name, drec);
        }else if(S_ISLNK(sb.st_mode)){
          // fprintf(stderr, "unknown entry type => link # mode = %o\n", sb.st_mode);
          drec.lcount++;
          disk_du_file(dirfd, d->d_name, drec);
        } else {
          drec.nfail++;
          fprintf(stderr, "unknown entry type. mode = %o\n", sb.st_mode);
        }

        break;
      }
      default: {
        drec.nfail++;
        fprintf(stderr, "not supported entry type %d\n", d->d_type);
      }
    }
  }

  drec.ccount = MAX(drec.ccount, n_entry);

  closedir(dirp);

  return;
}

void diskit_du(const char *path, diskitrec &drec) {
  int dirfd = open(path, O_RDONLY);
  drec.dir = path;
  diskit_du(dirfd, drec, 0);
  close(dirfd);
}


int diskit_snapshot(Tcl_Interp *interp, int dirfd, const char *path, struct diskstat &dstat) {
  int ret = TCL_OK;

  if (dirfd<0) {
    fprintf(stdout, "# diskit\n");
    time_t now = time(NULL);
    fprintf(stdout, "%% root = %s\n", path);
    fprintf(stdout, "%% R = ksize mtime\n");
    fprintf(stdout, "%% F = ksize mtime atime_diff uid\n");
    fprintf(stdout, "%% D = ksize mtime\n");
    fprintf(stdout, "%% P = ksize fcount dcount lcount mtime atime_diff\n");

    memset(&dstat, 0, sizeof(dstat));
    dstat.time = now;
  }

  if(dirfd < 0) {
    dirfd = open(path, O_RDONLY);
  } else {
    dirfd = openat(dirfd, path, O_RDONLY);
  }

  struct dirent *d;
  struct stat sb;
  DIR *dirp = fdopendir(dirfd);

  if (dirp == NULL) {
    fprintf(stderr, "fail to open dir '%s'\n");
    return TCL_ERROR;
  }


  std::vector<std::string> entries_file;
  std::vector<std::string> entries_dir;
  std::vector<std::string> entries_link;

  while((d = readdir(dirp)) != NULL){
    const char *name = d->d_name;
    if (name[0]=='.' && (name[1]=='.' || name[1] == '\0')) continue;

    int ret;
    switch(d->d_type){
      case DT_DIR : {
        entries_dir.push_back(name);
        break;
      }
      case DT_LNK : {
        entries_link.push_back(name);
        break;
      }
      case DT_REG : {
        entries_file.push_back(name);
        break;
      }
      default:
        break;
    }
  }


  fprintf(stdout, "\nR %s\n", path); // Root
  // fprintf(stdout, "A ...\n"); // Attribute
  // fprintf(stdout, "M ...\n"); // Meta

  {
    fstat(dirfd, &sb);
    long ksize = sb.st_blocks>>1;
    long mtime  = MAX(sb.st_mtime, sb.st_ctime);
    long atime  = sb.st_atime - mtime;

    fprintf(stdout, "* %ld %d\n", ksize, mtime); // Meta | Attribute
  }


  for(int i=0; i<entries_file.size(); i++){
    const char *name = entries_file[i].c_str();
    fprintf(stdout, "F %s\n", name);     // F = File

    fstatat(dirfd, name, &sb, AT_SYMLINK_NOFOLLOW);

    long ksize = sb.st_blocks>>1;
    long mtime  = MAX(sb.st_mtime, sb.st_ctime);
    long atime  = sb.st_atime;

    fprintf(stdout, "* %ld %d %+d %d\n", ksize, mtime, atime-mtime, sb.st_uid); // Meta | Attribute

    dstat.ksize_file += ksize;
    dstat.ksize_max = MAX(ksize, dstat.ksize_max);

    dstat.mtime_max = MAX(mtime, dstat.mtime_max);
    dstat.atime_max = MAX(atime, dstat.atime_max);
  }
  dstat.count_file = entries_file.size();

  for(int i=0; i<entries_dir.size(); i++){
    const char *name = entries_dir[i].c_str();
    fprintf(stdout, "D %s\n", name);     // D = Directory

    fstatat(dirfd, name, &sb, AT_SYMLINK_NOFOLLOW);

    long ksize = sb.st_blocks>>1;
    long mtime  = MAX(sb.st_mtime, sb.st_ctime);
    long atime  = sb.st_atime;

    fprintf(stdout, "* %ld %d\n", ksize, mtime); // Meta | Attribute

    dstat.ksize_dir += ksize;

    dstat.mtime_max = MAX(mtime, dstat.mtime_max);
    // XXX: do not track atime_max
  }
  dstat.count_dir = entries_dir.size();

  /*
  if(entries_dir.empty()){
    fprintf(stdout, "P %s\n", path); // Pop
  } else {
    fprintf(stdout, "\n");
  }
  */

  for(int i=0; i<entries_dir.size(); i++){
    const char *name = entries_dir[i].c_str();

    if(0 != faccessat(dirfd, name, R_OK, AT_SYMLINK_NOFOLLOW)){
      // cannot access
      perror("access fail");
      fprintf(stdout, "E %s\n", strerror(errno)); // Pop
      continue;
    }

    // TOOD:
    struct diskstat subdstat;
    memset(&subdstat, 0, sizeof(diskstat));
    subdstat.depth = dstat.depth + 1;

    diskit_snapshot(interp, dirfd, name, subdstat);

    dstat.ksize_dir  += subdstat.ksize_dir;
    dstat.ksize_file += subdstat.ksize_file;
    dstat.count_file += subdstat.count_file;
    dstat.count_dir  += subdstat.count_dir;
    dstat.count_link += subdstat.count_link;

    dstat.ksize_max = MAX(dstat.ksize_max, subdstat.ksize_max);
    dstat.mtime_max = MAX(dstat.mtime_max, subdstat.mtime_max);
    dstat.atime_max = MAX(dstat.atime_max, subdstat.atime_max);

  }
  fprintf(stdout, "P %s\n", path); // Pop
  fprintf(stdout, "* %ld %d %d %d %d %d\n", dstat.ksize_file + dstat.ksize_dir,
                   dstat.count_file, dstat.count_dir, dstat.count_link,
                   dstat.mtime_max, dstat.atime_max-dstat.mtime_max);

  closedir(dirp);
  close(dirfd);

  if (dstat.time > 0) {
    time_t now = time(NULL);
    fprintf(stdout, "# elapsed = %d\n", now - dstat.time);
  }

  return TCL_OK;
}

int diskit_find(Tcl_Interp *interp, int dirfd, const char *path, Tcl_Obj *script) {
  int ret = TCL_OK;

  if(dirfd < 0) {
    dirfd = open(path, O_RDONLY);
    Tcl_SetVar2(interp, "stat", "dir", path, 0);
  } else {
    dirfd = openat(dirfd, path, O_RDONLY);
  }

  struct dirent *d;
  struct stat sb;
  DIR *dirp = fdopendir(dirfd);

  if (dirp == NULL) {
    fprintf(stderr, "fail to open dir '%s'\n");
    return TCL_ERROR;
  }


  while((d = readdir(dirp)) != NULL){
    const char *name = d->d_name;
    if (name[0]=='.' && (name[1]=='.' || name[1] == '\0')) continue;

    Tcl_SetVar2(interp, "stat", "name", name, 0);

    int ret;
    switch(d->d_type){
      case DT_DIR : {
        Tcl_SetVar2(interp, "stat", "type", "d", 0);
        ret = Tcl_EvalObjEx(interp, script, 0);
        break;
      }
      case DT_LNK : {
        Tcl_SetVar2(interp, "stat", "type", "l", 0);
        Tcl_EvalObjEx(interp, script, 0);
        break;
      }
      case DT_REG : {
        Tcl_SetVar2(interp, "stat", "type", "f", 0);
        Tcl_EvalObjEx(interp, script, 0);
        break;
      }
      default: {
      }
    }

    if (ret == TCL_BREAK){
      break;
    }else if (ret == TCL_CONTINUE){
      ret = TCL_OK;
      continue;
    }else if (ret == TCL_OK){
      // continue;
    }else if (ret == TCL_ERROR){
      // TODO: error handling
      break;
    }


    if(d->d_type == DT_DIR){

      if(0 == faccessat(dirfd, d->d_name, R_OK, AT_SYMLINK_NOFOLLOW)){
          Tcl_Obj *dirObj = Tcl_GetVar2Ex(interp, "stat", "dir", 0);
          int length = 0;
          Tcl_GetStringFromObj(dirObj, &length);
          Tcl_AppendStringsToObj(dirObj, "/", name, NULL);

          ret = diskit_find(interp, dirfd, name, script);

          Tcl_SetObjLength(dirObj, length);
      }

      if (ret == TCL_BREAK){
        break;
      }else if (ret == TCL_OK){
        // continue;
      }else if (ret == TCL_ERROR){
        // TODO: error handling
        break;
      }
    }
  }
  closedir(dirp);
  close(dirfd);

  return ret;
}

int diskit_find_ObjCmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
  const char *dir    = Tcl_GetString(objv[1]);
  // TODO: use last argument
  Tcl_Obj *script = objv[2];

  diskit_find(interp, -1, dir, script);
  return TCL_OK;
}

int diskit_du_ObjCmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
  const char *dir = Tcl_GetString(objv[1]);

  total_size  = 0;
  total_block = 0;
  total_count = 0;

  Tcl_Obj *ret = Tcl_NewDictObj();

  diskitrec drec;

  drec.bsize     = 0;
  drec.ksize     = 0;
  drec.ksize_max = 0;
  drec.mtime     = 0;
  drec.atime     = 0;
  drec.ctime     = 0;
  drec.fcount    = 0;
  drec.dcount    = 0;
  drec.lcount    = 0;
  drec.ccount    = 0;
  drec.nfail     = 0;
  drec.elapse    = time(NULL);
  drec.mtime_max = drec.elapse + 3600*24*1; // Suppose no longer than 1 day
  drec.dir       = dir;
  drec.level     = 0;
  drec.depth     = 0;
  drec.atime_min = drec.elapse - 3600*24*30;  // within 30 days
  drec.mtime_min = drec.elapse - 3600*24*30;  // within 30 days
  drec.acount    = 0;
  drec.mcount    = 0;

  int dirfd = open(dir, O_RDONLY);
  diskit_du(dirfd, drec, 0);
  close(dirfd);

  drec.elapse  = time(NULL) - drec.elapse;

  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("bsize", -1), Tcl_NewLongObj(drec.bsize));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ksize", -1), Tcl_NewLongObj(drec.ksize));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ksize_max", -1), Tcl_NewLongObj(drec.ksize_max));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("mtime", -1),   Tcl_NewLongObj(drec.mtime)); // TOOD: why get -1?
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ctime", -1),   Tcl_NewLongObj(drec.ctime));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("atime", -1),   Tcl_NewLongObj(drec.atime));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("fcount", -1),  Tcl_NewIntObj(drec.fcount));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("dcount", -1),  Tcl_NewIntObj(drec.dcount));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("lcount", -1),  Tcl_NewIntObj(drec.lcount));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("nfail", -1),   Tcl_NewIntObj(drec.nfail));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("elapse", -1),  Tcl_NewIntObj(drec.elapse));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ccount", -1),  Tcl_NewIntObj(drec.ccount));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("depth", -1),   Tcl_NewIntObj(drec.depth)); // XXX:
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("acount", -1),  Tcl_NewIntObj(drec.acount));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("mcount", -1),  Tcl_NewIntObj(drec.mcount));

  Tcl_SetObjResult(interp, ret);
  return TCL_OK;
}

int diskit_df_ObjCmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
  const char *path = Tcl_GetString(objv[1]);
  const char *unit = "G";
  if(objc>2){
    unit = Tcl_GetString(objv[2]);
  }

  Tcl_Obj *ret = Tcl_NewDictObj();

  struct statvfs stat;

  if(0 != statvfs(path, &stat)){
    return TCL_ERROR;
  }

  uint64_t disk_free   = stat.f_bsize * stat.f_bfree;
  uint64_t disk_total  = stat.f_bsize * stat.f_blocks;
  uint64_t disk_avail  = stat.f_bsize * stat.f_bavail;

  if (0 == strcmp(unit,"G")){
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("free", -1),  Tcl_NewLongObj(disk_free>>30));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("total", -1), Tcl_NewLongObj(disk_total>>30));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("avail", -1), Tcl_NewLongObj(disk_total>>30));
  }else if (0 == strcmp(unit,"M")){
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("free", -1),  Tcl_NewLongObj(disk_free>>20));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("total", -1), Tcl_NewLongObj(disk_total>>20));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("avail", -1), Tcl_NewLongObj(disk_total>>20));
  }else if (0 == strcmp(unit,"K")){
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("free", -1),  Tcl_NewLongObj(disk_free>>10));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("total", -1), Tcl_NewLongObj(disk_total>>10));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("avail", -1), Tcl_NewLongObj(disk_total>>10));
  } else {
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("free", -1),  Tcl_NewLongObj(disk_free));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("total", -1), Tcl_NewLongObj(disk_total));
    Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("avail", -1), Tcl_NewLongObj(disk_avail));
  }

  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ffree", -1),  Tcl_NewLongObj(stat.f_ffree));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("ftotal", -1), Tcl_NewLongObj(stat.f_files));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("favail", -1), Tcl_NewLongObj(stat.f_favail));

  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("bsize", -1), Tcl_NewLongObj(stat.f_bsize));
  Tcl_DictObjPut(interp, ret, Tcl_NewStringObj("frsize", -1), Tcl_NewLongObj(stat.f_frsize));

  Tcl_SetObjResult(interp, ret);
  return TCL_OK;
}

const char *
file_type(int mode){
  mode = mode & S_IFMT;
  switch(mode){
    case DT_LNK: case S_IFLNK:
      return "link";
    case DT_REG: case S_IFREG:
      return "file";
    case DT_DIR: case S_IFDIR:
      return "dir";
    default:
      break;
  }
  return "";
}

#if 0

    struct stat {
        dev_t     st_dev;     /* ID of device containing file */
        ino_t     st_ino;     /* inode number */
        mode_t    st_mode;    /* protection */
        nlink_t   st_nlink;   /* number of hard links */
        uid_t     st_uid;     /* user ID of owner */
        gid_t     st_gid;     /* group ID of owner */
        dev_t     st_rdev;    /* device ID (if special file) */
        off_t     st_size;    /* total size, in bytes */
        blksize_t st_blksize; /* blocksize for file system I/O */
        blkcnt_t  st_blocks;  /* number of 512B blocks allocated */
        time_t    st_atime;   /* time of last access */
        time_t    st_mtime;   /* time of last modification */
        time_t    st_ctime;   /* time of last status change */
    };

#endif

int
diskit_readdir_ObjCmd(ClientData clientData, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[])
{

  int do_stat = 0, do_filter = 0, do_quiet = 0;
  const char *dirpath = NULL;

  for(int i=1; i<objc; i++){
    const char *arg = Tcl_GetString(objv[i]);

    if( 0==strcmp(arg, "-stat")){
      do_stat = 1;
    } else if( 0==strcmp(arg, "-filter")){
      // TODO:
    } else if( 0==strcmp(arg, "-quiet")){
      do_quiet = 1;
    } else {
      // TODO: check duplicate
      dirpath = arg;
    }
  }

  Tcl_Obj *result = Tcl_NewListObj(0, NULL);

  errno = 0;
  DIR *dirp = opendir(dirpath);

  /*
       EACCES Permission denied.

       EBADF  fd is not a valid file descriptor opened for reading.

       EMFILE Too many file descriptors in use by process.

       ENFILE Too many files are currently open in the system.

       ENOENT Directory does not exist, or name is an empty string.

       ENOMEM Insufficient memory to complete the operation.

       ENOTDIR
              name is not a directory.
  */


  if(dirp == NULL) {
    size_t buflen = 2014;
    char   buf[buflen];
    const char *errno_text = strerror_r(errno, buf, buflen);  // thread safe version of strerror(errno)
    if(do_quiet){
      return TCL_OK;
    } else {
      fprintf(stderr, "opendir error %s\n", dirpath);
      return TCL_ERROR;
    }
  }

  struct dirent *dp;
  struct stat sb;
  char   pathname[4096];
  int    has_dtype = 0;

  #ifdef _BSD_SOURCE
  has_dtype = 1;
  #endif

  /* Ref: man readdir_r */
  int entryp_len = offsetof(struct dirent, d_name) +
           pathconf(dirpath, _PC_NAME_MAX) + 1;
  struct dirent *entryp = (struct dirent *) malloc(entryp_len);

  do {
    errno = 0;

    #if 0
    dp = readdir(dirp); // This is not thread safe
    #endif

    int readdir_ok = readdir_r(dirp, entryp, &dp);

    if(dp==NULL) break;
    const char *name = dp->d_name;

    if(name[0]=='.' && (name[1]=='\0' || name[1]=='.' && name[2]=='\0')) {
      continue;
    }

    unsigned char d_type = 0;

    int stat_ok = 0;
    if (do_stat) {
      strcpy(pathname, dirpath);
      strcat(pathname, "/");
      strcat(pathname, name);
      stat_ok = lstat(pathname, &sb);       // TODO:
    }

    if (do_filter) {
      if(do_stat) {
        d_type = (sb.st_mode & S_IFMT);
      } else {
        d_type = dp->d_type;
      }

      switch(d_type){
        case DT_LNK: case S_IFLNK:
          break;
        case DT_REG: case S_IFREG:
          break;
        case DT_DIR: case S_IFDIR:
          break;
        case DT_UNKNOWN:
          break;
        default:
          break;
      }
    }

    // fprintf(stderr, "add entry %s\n", name);
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj(name, -1));

    if(do_stat){
      Tcl_Obj *stat_dict = Tcl_NewDictObj();
      long  ksize = sb.st_blocks>>1;
      long  mtime  = MAX(sb.st_mtime, sb.st_ctime);
      long  atime  = sb.st_atime;
      long long size = sb.st_size;

      if(stat_ok==0){
        Tcl_DictObjPut(interp, stat_dict, key_type, Tcl_NewStringObj(file_type(sb.st_mode), -1));
      } else {
        Tcl_DictObjPut(interp, stat_dict, key_type, key_empty);
      }
      Tcl_DictObjPut(interp, stat_dict, key_size,  Tcl_NewLongObj(size));
      Tcl_DictObjPut(interp, stat_dict, key_ksize, Tcl_NewLongObj(ksize));
      Tcl_DictObjPut(interp, stat_dict, key_mtime, Tcl_NewLongObj(mtime));
      Tcl_DictObjPut(interp, stat_dict, key_atime, Tcl_NewLongObj(atime));

      Tcl_ListObjAppendElement(interp, result, stat_dict);
    }

  }while(1);

  free(entryp);

  closedir(dirp);

  Tcl_SetObjResult(interp, result);
  return TCL_OK;

  struct dirent **namelist;
  int namelist_size;
  namelist_size = scandir(dirpath, &namelist, NULL, NULL);

  if(namelist_size<0){
    return TCL_ERROR;
  }
  int n = namelist_size;
  while(n--){
    const char *name = namelist[n]->d_name;
    if(name[0]=='.' && (name[1]=='\0' || name[1]=='.' && name[2]=='\0')) {
      continue;
    }
    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj(name, -1));
  }
  free(namelist);

  Tcl_SetObjResult(interp, result);
  return TCL_OK;
}

extern "C" {

int Diskit_Init(Tcl_Interp *interp) {

#ifdef USE_TCL_STUBS
 if(Tcl_InitStubs(interp, "8.4", 0) == NULL) {
   fprintf(stderr, "Error: Tcl_InitStubs\n");
   return TCL_ERROR;
 }
#else
 if(Tcl_PkgRequire(interp, "Tcl", "8.4", 0) == NULL) {
   fprintf(stderr, "Error: package require Tcl 8.4\n");
   return TCL_ERROR;
 }
#endif

 key_empty = Tcl_NewStringObj("", -1);
 key_type  = Tcl_NewStringObj("type", -1);
 key_size  = Tcl_NewStringObj("size", -1);
 key_ksize = Tcl_NewStringObj("ksize", -1);
 key_mtime = Tcl_NewStringObj("mtime", -1);
 key_atime = Tcl_NewStringObj("atime", -1);

 Tcl_IncrRefCount(key_empty);
 Tcl_IncrRefCount(key_type);
 Tcl_IncrRefCount(key_size);
 Tcl_IncrRefCount(key_ksize);
 Tcl_IncrRefCount(key_mtime);
 Tcl_IncrRefCount(key_atime);

 Tcl_PkgProvide(interp, "diskit", "0.1");
 Tcl_CreateNamespace(interp, "diskit", NULL, NULL);
 //Tcl_CreateObjCommand(interp, "diskit",         diskit_du_ObjCmd, NULL, NULL);
 Tcl_CreateObjCommand(interp, "diskit::df",       diskit_df_ObjCmd, NULL, NULL);
 Tcl_CreateObjCommand(interp, "diskit::statvfs",  diskit_df_ObjCmd, NULL, NULL);
 Tcl_CreateObjCommand(interp, "diskit::du",       diskit_du_ObjCmd, NULL, NULL);
 Tcl_CreateObjCommand(interp, "diskit::find",     diskit_find_ObjCmd, NULL, NULL);
 Tcl_CreateObjCommand(interp, "diskit::readdir",  diskit_readdir_ObjCmd, NULL, NULL);
 return TCL_OK;
}

}


#ifdef __MAIN__
static int
Tcl_AppInit_Main(Tcl_Interp *interp)
{



  return TCL_OK;
}
    // Tcl_Main(argc, argv, Tcl_AppInit_Main);

int main(int argc, char *argv[]){

  const char *act = argc>1?argv[1]:"";

  if(0 == strcmp(act, "eval")) {

    Tcl_Interp *interp = Tcl_CreateInterp();
    Tcl_Init(interp);
    Diskit_Init(interp);

    const char *script = argc>2?argv[2]:NULL;
    if(script == NULL) {
      script = "puts hello";
    }
    Tcl_Eval(interp, script);

    printf("%s\n", Tcl_GetStringResult(interp));
    Tcl_DeleteInterp(interp);
    return 0;
  }


  if(0 == strcmp(act, "snap")) {
    const char *dirpath = argv[2];
    struct diskstat dstat;
    diskit_snapshot(NULL, -1, dirpath, dstat);
    return 0;
  }

  // total_size  = 0;
  // total_block = 0;
  // total_count = 0;
  // printf("sizeof(long) = %d\n", sizeof(long));
  // printf("sizeof(long long) = %d\n", sizeof(long long));
  // printf("sizeof(uint64_t) = %d\n", sizeof(uint64_t));
  // printf("sizeof(size_t) = %d\n", sizeof(size_t));
  // du(argv[1]);
  // printf("total size  = %ld\n", total_size);
  // printf("total size  = %jd\n", total_size);
  // printf("total block = %ld\n", total_block*512);
  // printf("total count = %ld\n", total_count);
  return 0;
}
#endif

/*
 * TODO: use '-verbose' to print more message
 * TODO: use '-queit' to supress more message
 */

