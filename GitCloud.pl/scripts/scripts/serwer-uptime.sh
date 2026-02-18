#!/bin/bash
# ================================
# GitCloud | Server Uptime
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/login"
OUT_FILE="$OUT_DIR/serwer-uptime.txt"

mkdir -p "$OUT_DIR"

# uptime in seconds
UPTIME_SEC=$(cut -d. -f1 /proc/uptime)

DAYS=$((UPTIME_SEC / 86400))
HOURS=$(((UPTIME_SEC % 86400) / 3600))
MINUTES=$(((UPTIME_SEC % 3600) / 60))
SECONDS=$((UPTIME_SEC % 60))

TXT="Uptime: ${DAYS}d ${HOURS}h ${MINUTES}m ${SECONDS}s"

echo "$TXT" > "$OUT_FILE"

echo "$TXT"
