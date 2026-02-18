#!/bin/bash

BACKUP_BASE="/home/gitcloud/backup-database"
OUT="/home/gitcloud/statistics/stats-top-processes.txt"

> "$OUT"

shopt -s nullglob

for BACKUP in "$BACKUP_BASE"/backup-*; do

  [ ! -d "$BACKUP" ] && continue

  TS=$(basename "$BACKUP" | sed 's/backup-//' | sed 's/_/ /')

  CPU="$BACKUP/cpu-load/cpu-top.txt"
  RAM="$BACKUP/ram/ram-top.txt"

  [ ! -f "$CPU" ] && continue
  [ ! -f "$RAM" ] && continue

  CPU_TOP=$(awk -F'-' '
  /%/ {
    gsub(/,/, ".", $2)
    gsub(/ %/, "", $2)
    split($1,a,"(")
    printf "%s:%s%%, ", a[1], $2
  }' "$CPU" | head -n 3 | sed 's/, $//')

  RAM_TOP=$(awk -F'-' '
  /MB/ {
    gsub(/,/, ".", $2)
    gsub(/ MB/, "", $2)
    split($1,a,"(")
    printf "%s:%sMB, ", a[1], $2
  }' "$RAM" | head -n 3 | sed 's/, $//')

  [ -z "$CPU_TOP" ] && continue
  [ -z "$RAM_TOP" ] && continue

  echo "$TS | CPU_TOP=$CPU_TOP | RAM_TOP=$RAM_TOP" >> "$OUT"

done
