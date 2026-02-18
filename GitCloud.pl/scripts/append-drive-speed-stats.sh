#!/bin/bash

BASE="/home/gitcloud/backup-database"
OUT="/home/gitcloud/statistics/stats-drive-speed.txt"

# создаём файл, если его нет
touch "$OUT"

shopt -s nullglob

for BACKUP in "$BASE"/backup-*; do
  FILE="$BACKUP/drive/speed-drive.txt"
  [[ ! -f "$FILE" ]] && continue

  TS=$(basename "$BACKUP" | sed 's/^backup-//' | sed 's/_/ /')

  # если этот timestamp уже есть — пропускаем
  grep -q "^$TS |" "$OUT" && continue

  C_READ=$(awk '
    /^Drive: C:/ {f=1; next}
    f && /^Drive:/ {exit}
    f && /Read:/ {print $(NF-1); exit}
  ' "$FILE")

  C_WRITE=$(awk '
    /^Drive: C:/ {f=1; next}
    f && /^Drive:/ {exit}
    f && /Write:/ {print $(NF-1); exit}
  ' "$FILE")

  [[ -z "$C_READ" || -z "$C_WRITE" ]] && continue

  echo "$TS | C_READ=${C_READ}MB/s | C_WRITE=${C_WRITE}MB/s" >> "$OUT"
done
