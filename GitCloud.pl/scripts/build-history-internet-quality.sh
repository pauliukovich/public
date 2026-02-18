#!/bin/bash

BASE_DIR="/home/gitcloud/backup-database"
OUTPUT="/home/gitcloud/statistics/stats-internet-quality.txt"

# если файла нет — создаём, но НЕ обнуляем
touch "$OUTPUT"

for dir in "$BASE_DIR"/backup-*; do
    MON="$dir/monitoring/monitoring.txt"
    [[ ! -f "$MON" ]] && continue

    # timestamp из имени папки
    TS=$(basename "$dir" | sed 's/backup-//' | tr '_' ' ' | tr '-' ':')

    # если этот timestamp уже есть — пропускаем
    grep -q "^$TS |" "$OUTPUT" && continue

    # вытаскиваем Avg ms
    ms_111=$(grep "Target 1.1.1.1" "$MON" | grep -oP 'Avg\s+\K[0-9,]+' | tr ',' '.')
    ms_888=$(grep "Target 8.8.8.8" "$MON" | grep -oP 'Avg\s+\K[0-9,]+' | tr ',' '.')
    ms_google=$(grep "Target google.com" "$MON" | grep -oP 'Avg\s+\K[0-9,]+' | tr ',' '.')

    # если чего-то нет — не пишем мусор
    [[ -z "$ms_111" || -z "$ms_888" || -z "$ms_google" ]] && continue

    echo "$TS | 1.1.1.1=${ms_111}ms | 8.8.8.8=${ms_888}ms | google.com=${ms_google}ms" >> "$OUTPUT"
done
