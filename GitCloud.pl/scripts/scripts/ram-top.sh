#!/bin/bash
# ================================
# GitCloud | RAM Top 5 Consumers
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/ram"
OUT_FILE="$OUT_DIR/ram-top.txt"

mkdir -p "$OUT_DIR"

TIME=$(date "+%Y-%m-%d %H:%M:%S")

{
echo "RAM TOP 5 PROCESSES"
echo "Time: $TIME"
echo "------------------------------------"

# ps:
# RSS = resident set size in KB
ps -eo pid,comm,rss --sort=-rss | head -n 6 | tail -n 5 | while read PID NAME RSS; do
    RAM_MB=$(awk "BEGIN { printf \"%.1f\", $RSS/1024 }")
    echo "$NAME (PID $PID) - $RAM_MB MB"
done

echo "------------------------------------"
} > "$OUT_FILE"
