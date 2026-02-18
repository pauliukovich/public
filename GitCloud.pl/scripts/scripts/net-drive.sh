#!/bin/bash
# ================================
# GitCloud | Net Drive Status
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/drive"
OUT_FILE="$OUT_DIR/net-drive.txt"

# MOUNTED path of network share
NET_PATH="/mnt/gitcloud"   # ← поменяй при необходимости

mkdir -p "$OUT_DIR"

# Clear file
> "$OUT_FILE"

write_line() {
    echo "$1" >> "$OUT_FILE"
}

SERVER_NAME=$(hostname)
NOW=$(date "+%Y-%m-%d %H:%M:%S")

write_line "===== NET DRIVE STATUS ====="
write_line "Server : $SERVER_NAME"
write_line "Date   : $NOW"
write_line ""

# ---------- Check path ----------
if [[ ! -d "$NET_PATH" ]]; then
    write_line "Path         : $NET_PATH"
    write_line "Status       : ERROR - path not found or not mounted"
    exit 0
fi

# ---------- Disk usage ----------
DF_OUT=$(df -B1 "$NET_PATH" 2>/dev/null | tail -n1)

if [[ -z "$DF_OUT" ]]; then
    write_line "Path         : $NET_PATH"
    write_line "Status       : ERROR - cannot read size (check access / mount)"
    exit 0
fi

TOTAL_BYTES=$(echo "$DF_OUT" | awk '{print $2}')
USED_BYTES=$(echo "$DF_OUT"  | awk '{print $3}')
FREE_BYTES=$(echo "$DF_OUT"  | awk '{print $4}')

if [[ "$TOTAL_BYTES" -le 0 ]]; then
    write_line "Path         : $NET_PATH"
    write_line "Status       : ERROR - invalid size"
    exit 0
fi

TOTAL_GB=$(awk "BEGIN { printf \"%.1f\", $TOTAL_BYTES/1024/1024/1024 }")
USED_GB=$(awk  "BEGIN { printf \"%.1f\", $USED_BYTES /1024/1024/1024 }")
FREE_GB=$(awk  "BEGIN { printf \"%.1f\", $FREE_BYTES /1024/1024/1024 }")
USED_PCT=$(awk "BEGIN { printf \"%.1f\", ($USED_BYTES/$TOTAL_BYTES)*100 }")

# ---------- Output ----------
write_line "Path         : $NET_PATH"
write_line ""
write_line "Total Space  : $TOTAL_GB GB"
write_line "Used Space   : $USED_GB GB"
write_line "Free Space   : $FREE_GB GB"
write_line "Used Percent : $USED_PCT %"
