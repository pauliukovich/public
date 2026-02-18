#!/bin/bash
# ================================
# GitCloud | Disk Speed (Linux)
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/drive"
OUT_FILE="$OUT_DIR/speed-drive.txt"

mkdir -p "$OUT_DIR"

# Targets: mountpoint -> label
declare -A TARGETS=(
  ["/"]="C:"
  ["/mnt/gitcloud"]="G:"
)

INTERVAL=1   # seconds

now=$(date "+%Y-%m-%d %H:%M:%S")

echo "Disk speed report ($now)" > "$OUT_FILE"
echo "----------------------------------------" >> "$OUT_FILE"

get_disk() {
    df "$1" 2>/dev/null | tail -1 | awk '{print $1}'
}

read_stats() {
    DEV="$1"
    grep " $DEV " /proc/diskstats
}

for MOUNT in "${!TARGETS[@]}"; do
    LABEL="${TARGETS[$MOUNT]}"

    if ! mountpoint -q "$MOUNT"; then
        {
            echo "Drive: $LABEL"
            echo "No data available"
            echo ""
        } >> "$OUT_FILE"
        continue
    fi

    DEV=$(get_disk "$MOUNT")
    DEV=$(basename "$DEV")

    S1=$(read_stats "$DEV")
    sleep "$INTERVAL"
    S2=$(read_stats "$DEV")

    if [[ -z "$S1" || -z "$S2" ]]; then
        {
            echo "Drive: $LABEL"
            echo "No data available"
            echo ""
        } >> "$OUT_FILE"
        continue
    fi

    R1=$(echo "$S1" | awk '{print $6}')
    W1=$(echo "$S1" | awk '{print $10}')
    R2=$(echo "$S2" | awk '{print $6}')
    W2=$(echo "$S2" | awk '{print $10}')

    SECTOR_SIZE=512

    READ_MB=$(awk "BEGIN { printf \"%.2f\", (($R2-$R1)*$SECTOR_SIZE)/1024/1024/$INTERVAL }")
    WRITE_MB=$(awk "BEGIN { printf \"%.2f\", (($W2-$W1)*$SECTOR_SIZE)/1024/1024/$INTERVAL }")

    {
        echo "Drive: $LABEL"
        echo "Read:  $READ_MB MB/s"
        echo "Write: $WRITE_MB MB/s"
        echo ""
    } >> "$OUT_FILE"

done
