
#include <stdlib.h>
#include <stdio.h>
#include <dirent.h>
#include <fcntl.h>
#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define max(a,b) (a>b?a:b)
#define min(a,b) (a<b?a:b)


int try_readdir() {

  DIR *dirp = opendir(".");

  while(1){
    struct dirent *entry = readdir(dirp);

    if(entry==NULL) {
      break;
    }

    const char *pathname = entry->d_name;

    struct stat stat; 

    lstat(pathname, &stat);

    printf("%d\t%d\t%d\t%s\n", entry->d_ino, stat.st_size, stat.st_mtim.tv_sec, entry->d_name);
  }
  closedir(dirp); 

  return 1;
} 

int try_scandir(){
    struct dirent **namelist;
    int n;

    n = scandirat(AT_FDCWD, ".", &namelist, NULL, NULL);
    if (n < 0)
        perror("scandir");
    else {
        while (n--) {
            printf("%s\n", namelist[n]->d_name);
            free(namelist[n]);
        }
        free(namelist);
    }
    return 0;
} 

#define WALKDIR_DEPTH 1 

struct dirstat {
  long nfile; 
  long ndir; 
  long nlink; 

  long size_file;
  long size_dir;
  long size_link;

  long mtime_max;
  long atime_max;
};

int
walkdir(const char *dirpath, struct dirstat *dstat, int flags)
{

  // open(dirpath), 

  DIR *dirp = opendir(dirpath);

  // int openat(int dirfd, const char *pathname, int flags);

  if (dstat!=NULL){
    dstat->mtime_max = 0;
    dstat->atime_max = 0;
    dstat->nfile     = 0;
    dstat->ndir      = 0;
    dstat->nlink     = 0;
    dstat->size_file = 0;
    dstat->size_link = 0;
    dstat->size_dir  = 0;
  }

  while(1){
    struct dirent *entry = readdir(dirp);

    if(entry==NULL) {
      break;
    }

    const char *name = entry->d_name;
 
    if (name[0]=='.' && (name[1]=='\0' || (name[1]=='.' && name[2]=='\0'))) {
      continue;
    }

    char pathname[1024] = "\0";
    strcat(pathname, dirpath); 
    strcat(pathname, "/"); 
    strcat(pathname, name); 

    struct stat sb; 

    // printf("debug: lstat %s\n", pathname);
    lstat(pathname, &sb);

    int mode = sb.st_mode;

    int is_dir = S_ISDIR(mode);

    if(is_dir){
      if (dstat!=NULL){
        dstat->ndir++;
      }
      if (flags & WALKDIR_DEPTH) {
        struct dirstat _dstat;
        walkdir(pathname, &_dstat, flags);
        printf("%d\t%d\t%d\t%s/%s/\n", sb.st_mtim.tv_sec, sb.st_atim.tv_sec, sb.st_size, dirpath, entry->d_name);
        if(dstat != NULL) {
         dstat->nfile     += _dstat.nfile;
         dstat->ndir      += _dstat.ndir;
         dstat->nlink     += _dstat.nlink;
         dstat->size_file += _dstat.size_file;
         dstat->mtime_max  = max(dstat->mtime_max, _dstat.mtime_max);
         dstat->atime_max  = max(dstat->atime_max, _dstat.atime_max);
        } 
      } else {
        printf("%d\t%d\t%d\t%s/%s/\n", sb.st_mtim.tv_sec, sb.st_atim.tv_sec, sb.st_size, dirpath, entry->d_name);
        walkdir(pathname, NULL, flags);
      }
    } else if(S_ISREG(mode)){
      if (dstat!=NULL){
        dstat->nfile++;
        dstat->size_file += sb.st_size;
        dstat->mtime_max  = max(dstat->mtime_max, max(sb.st_mtim.tv_sec, sb.st_ctim.tv_sec));
        dstat->atime_max  = max(dstat->atime_max, sb.st_atim.tv_sec);
      }
      printf("%d\t%d\t%d\t%s/%s\n", sb.st_mtim.tv_sec, sb.st_atim.tv_sec, sb.st_size, dirpath, entry->d_name);
    } else if(S_ISLNK(mode)){
      if (dstat!=NULL){
        dstat->nlink++;
        dstat->size_link += sb.st_size;
      }
    } else {
      // XXX: skip other types
    }
  }
  closedir(dirp); 

  if (dstat!=NULL){
    printf("\t size_file = %d , nfile = %d , ndir = %d , nlink = %d\n", dstat->size_file, dstat->nfile, dstat->ndir, dstat->nlink);
    printf("\t mtime_max = %d , atime_max = %d\n", dstat->mtime_max, dstat->atime_max);
  }

  return 1;

}

int
walkdirat(int dirfd, const char *dirp)
{

  return 1;
}



int
main(int argc, char **argv)
{
  const char *act = argc>1?argv[1]:"";

  if( 0 == strcmp(act, "try-scandir") ){
    return try_scandir();
  }

  if( 0 == strcmp(act, "try-readdir") ){
    return try_readdir();
  }

  const char *dirpath = argv[1];

  int flags = 0; 
  int i;
  for(i=2; i<argc; i++){
    if(0 == strcmp(argv[i], "-depth")){
      flags |= WALKDIR_DEPTH;
    }
  }

  walkdir(dirpath, NULL, flags);

  return 0;
}

