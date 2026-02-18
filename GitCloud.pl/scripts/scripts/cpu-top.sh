#!/usr/bin/env bash
# ================================
# GitCloud | CPU Top Processes (relative)
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/cpu-load"
OUT_FILE="$OUT_DIR/cpu-top.txt"

mkdir -p "$OUT_DIR"
: > "$OUT_FILE"

SERVER="$(hostname)"
NOW="$(date "+%Y-%m-%d %H:%M:%S")"

INTERVAL=5
HZ="$(getconf CLK_TCK)"

# ---------- CPU total ticks ----------
cpu_total() {
    awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8}' /proc/stat
}

# ---------- process snapshot ----------
snapshot() {
    for p in /proc/[0-9]*; do
        pid="${p#/proc/}"
        stat="$p/stat"
        comm="$p/comm"
        [[ -r "$stat" ]] || continue

        read -r _ _ _ _ _ _ _ _ _ _ _ _ utime stime _ < "$stat" 2>/dev/null || continue
        [[ "$utime" =~ ^[0-9]+$ ]] || continue
        [[ "$stime" =~ ^[0-9]+$ ]] || continue

        name="$(cat "$comm" 2>/dev/null || echo "$pid")"
        printf "%s %s %s %s\n" "$pid" "$utime" "$stime" "$name"
    done
}

TMP1="$(mktemp)"
TMP2="$(mktemp)"
trap 'rm -f "$TMP1" "$TMP2"' EXIT

CPU1_TOTAL="$(cpu_total)"
snapshot > "$TMP1"
sleep "$INTERVAL"
CPU2_TOTAL="$(cpu_total)"
snapshot > "$TMP2"

TOTAL_DELTA=$((CPU2_TOTAL - CPU1_TOTAL))
[[ "$TOTAL_DELTA" -le 0 ]] && TOTAL_DELTA=1

RESULTS="$(awk -v total="$TOTAL_DELTA" '
    NR==FNR { p[$1]=$2+$3; n[$1]=$4; next }
    {
        pid=$1
        now=$2+$3
        if (!(pid in p)) next
        d=now-p[pid]
        if (d<=0) next
        pct=(d/total)*100
        printf "%.3f|%s|%s\n", pct, pid, n[pid]
    }
' "$TMP1" "$TMP2" | sort -t"|" -k1,1nr | head -5)"

{
    echo "===== CPU TOP PROCESSES ====="
    echo "Server   : $SERVER"
    echo "Date     : $NOW"
    echo "Interval : ${INTERVAL}s (relative)"
    echo ""

    if [[ -z "$RESULTS" ]]; then
        echo "No processes data available."
    else
        echo "TOP 5 PROCESSES:"
        while IFS='|' read -r CPU PID NAME; do
            CPU1="$(awk "BEGIN{printf \"%.2f\", $CPU}")"
            echo "$NAME (PID $PID) - $CPU1 %"
        done <<< "$RESULTS"
    fi
} > "$OUT_FILE"
