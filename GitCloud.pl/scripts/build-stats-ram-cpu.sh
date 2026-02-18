#!/bin/bash

BACKUP_DIR="/home/gitcloud/backup-database"
OUT_DIR="/home/gitcloud/statistics"
OUT_FILE="$OUT_DIR/stats-ram-cpu.txt"

mkdir -p "$OUT_DIR"

# Создаём файл, если его нет. Заголовок пишем только один раз.
if [[ ! -f "$OUT_FILE" ]]; then
  echo "# time | RAM_USED | CPU_LOAD" > "$OUT_FILE"
fi

# Идём по бэкапам в хронологическом порядке
for dir in "$BACKUP_DIR"/backup-*; do
  [[ ! -d "$dir" ]] && continue

  name=$(basename "$dir")

  if [[ ! $name =~ backup-([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
    continue
  fi

  DATE="${BASH_REMATCH[1]}"
  TIME="${BASH_REMATCH[2]//-/:}"
  TS="$DATE $TIME"

  # Если этот timestamp уже записан — пропускаем
  grep -q "^$TS |" "$OUT_FILE" && continue

  RAM_FILE="$dir/drive/serverdrive.txt"
  CPU_FILE="$dir/cpu-load/cpu-load.txt"

  RAM_USED="N/A"
  CPU_LOAD="N/A"

  if [[ -f "$RAM_FILE" ]]; then
    RAM_USED=$(awk '
      /\[RAM - SUMMARY\]/ {found=1; next}
      found && /Used \(%\)/ {
        gsub(/[% ]/, "", $NF)
        print $NF
        exit
      }
    ' "$RAM_FILE")
    [[ -z "$RAM_USED" ]] && RAM_USED="N/A"
  fi

  if [[ -f "$CPU_FILE" ]]; then
    CPU_LOAD=$(awk -F':' '/Current Load/ {
      gsub(/[% ]/, "", $2)
      print $2
      exit
    }' "$CPU_FILE")
    [[ -z "$CPU_LOAD" ]] && CPU_LOAD="N/A"
  fi

  echo "$TS | RAM_USED=$RAM_USED | CPU_LOAD=$CPU_LOAD" >> "$OUT_FILE"
done
