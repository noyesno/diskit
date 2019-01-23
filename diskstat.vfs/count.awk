
/^[FDRPG]/ {
  type = $1;
  sum[type, "count"] ++;
  sum[type, "name"] += length($0);
  getline;
  sum[type, "attr"] += length($0);
  sum[type, "ksize"] += $2;
}

END {
  for(k in sum){
    print sum[k],k;
  }
}
