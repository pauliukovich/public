#!/bin/bash
# ================================
# GitCloud | CPU Load Monitor
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/cpu-load"
OUT_FILE="$OUT_DIR/cpu-load.txt"

mkdir -p "$OUT_DIR"

SERVER=$(hostname)
NOW=$(date "+%Y-%m-%d %H:%M:%S")

# ---------- CPU INFO ----------
CPU_NAME=$(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^ *//')
CPU_CORES=$(lscpu | awk -F: '/Core\(s\) per socket/ {print $2}' | sed 's/^ *//')
CPU_SOCKETS=$(lscpu | awk -F: '/Socket\(s\)/ {print $2}' | sed 's/^ *//')
CPU_LOGICAL=$(nproc)

[[ -z "$CPU_CORES" ]] && CPU_CORES="N/A"
[[ -z "$CPU_LOGICAL" ]] && CPU_LOGICAL="N/A"

# ---------- CPU LOAD (5 samples x 2 sec) ----------
SAMPLES=5
INTERVAL=2
VALUES=()

get_cpu_usage() {
    # returns total CPU usage %
    awk '
    /^cpu / {
        idle=$5; total=0;
        for (i=2;i<=NF;i++) total+=$i;
        print total, idle
    }' /proc/stat
}

read TOTAL1 IDLE1 < <(get_cpu_usage)

for ((i=0;i<SAMPLES;i++)); do
    sleep "$INTERVAL"
    read TOTAL2 IDLE2 < <(get_cpu_usage)

    DT=$((TOTAL2 - TOTAL1))
    DI=$((IDLE2 - IDLE1))

    if [[ "$DT" -gt 0 ]]; then
        LOAD=$(awk "BEGIN { printf \"%.1f\", (1 - $DI/$DT) * 100 }")
        VALUES+=("$LOAD")
    fi

    TOTAL1=$TOTAL2
    IDLE1=$IDLE2
done

if [[ "${#VALUES[@]}" -eq 0 ]]; then
    NOW_LOAD=0
    AVG_LOAD=0
    MAX_LOAD=0
    MIN_LOAD=0
else
    NOW_LOAD="${VALUES[-1]}"
    AVG_LOAD=$(printf "%s\n" "${VALUES[@]}" | awk '{s+=$1} END {printf "%.1f", s/NR}')
    MAX_LOAD=$(printf "%s\n" "${VALUES[@]}" | sort -nr | head -1)
    MIN_LOAD=$(printf "%s\n" "${VALUES[@]}" | sort -n  | head -1)
fi

# ---------- CPU TEMPERATURE ----------
CPU_TEMP="N/A"
TEMP_SOURCE="N/A"

if command -v sensors >/dev/null 2>&1; then
    TEMP=$(sensors 2>/dev/null | awk '/Package id 0|Tctl|Tdie/ {print $4}' | tr -d '+°C' | head -1)
    if [[ -n "$TEMP" ]]; then
        CPU_TEMP="$TEMP"
        TEMP_SOURCE="lm-sensors"
    fi
elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    CPU_TEMP=$(awk "BEGIN { printf \"%.1f\", $TEMP_RAW/1000 }")
    TEMP_SOURCE="thermal_zone0"
fi

# ---------- WRITE OUTPUT ----------
{
echo "===== CPU LOAD ====="
echo "Server : $SERVER"
echo "Date   : $NOW"
echo ""

echo "CPU Model        : $CPU_NAME"
echo "Cores / Logical  : $CPU_CORES / $CPU_LOGICAL"
echo ""

echo "Current Load     : $NOW_LOAD %"
echo "Average Load 10s : $AVG_LOAD %"
echo "Max Load 10s     : $MAX_LOAD %"
echo "Min Load 10s     : $MIN_LOAD %"
echo ""

if [[ "$CPU_TEMP" != "N/A" ]]; then
    echo "CPU Temperature : $CPU_TEMP °C"
    echo "Temp Source     : $TEMP_SOURCE"
else
    echo "CPU Temperature : N/A (no sensor available)"
    echo "Temp Source     : $TEMP_SOURCE"
fi
} > "$OUT_FILE"
