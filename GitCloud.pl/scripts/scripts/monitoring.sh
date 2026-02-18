#!/bin/bash
# ================================
# GitCloud | Internet Monitoring
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/monitoring"
OUT_FILE="$OUT_DIR/monitoring.txt"

mkdir -p "$OUT_DIR"

NOW=$(date "+%Y-%m-%d %H:%M:%S")
SERVER=$(hostname)

# ---------- Helper: ping stats ----------
get_ping_stats() {
    TARGET="$1"
    COUNT=4

    PING_OUTPUT=$(ping -c $COUNT -W 2 "$TARGET" 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        SENT=$COUNT
        RECEIVED=$(echo "$PING_OUTPUT" | grep -o "received, [0-9]*" | awk '{print $2}')
        LOST=$((SENT - RECEIVED))
        LOSS_PCT=$(awk "BEGIN { printf \"%.1f\", ($LOST/$SENT)*100 }")
        AVG_LAT=$(echo "$PING_OUTPUT" | grep rtt | awk -F'/' '{print $5}')
        ONLINE="true"
        AVG_LAT="${AVG_LAT} ms"
    else
        SENT=$COUNT
        RECEIVED=0
        LOST=$COUNT
        LOSS_PCT="100"
        AVG_LAT="N/A"
        ONLINE="false"
    fi

    echo "$TARGET|$SENT|$RECEIVED|$LOSS_PCT %|$AVG_LAT|$ONLINE"
}

# ---------- External IP & ISP ----------
EXT_IP="N/A"
ISP_NAME="N/A"
ISP_CITY="N/A"
ISP_COUNTRY="N/A"

IPINFO=$(curl -s --max-time 10 https://ipinfo.io/json)
if [[ -n "$IPINFO" ]]; then
    EXT_IP=$(echo "$IPINFO" | jq -r '.ip // "N/A"')
    ISP_NAME=$(echo "$IPINFO" | jq -r '.org // "N/A"')
    ISP_CITY=$(echo "$IPINFO" | jq -r '.city // "N/A"')
    ISP_COUNTRY=$(echo "$IPINFO" | jq -r '.country // "N/A"')
fi

# ---------- Routing info ----------
GATEWAY="N/A"
ROUTE_METRIC="N/A"
IFACE_ALIAS="N/A"
PROFILE_NAME="N/A"
PROFILE_TYPE="N/A"

DEFAULT_ROUTE=$(ip route show default 2>/dev/null | head -n1)
if [[ -n "$DEFAULT_ROUTE" ]]; then
    GATEWAY=$(echo "$DEFAULT_ROUTE" | awk '{print $3}')
    IFACE_ALIAS=$(echo "$DEFAULT_ROUTE" | awk '{print $5}')
    ROUTE_METRIC=$(echo "$DEFAULT_ROUTE" | grep -o "metric [0-9]*" | awk '{print $2}')
    [[ -z "$ROUTE_METRIC" ]] && ROUTE_METRIC="N/A"
    PROFILE_NAME="Linux"
    PROFILE_TYPE="Default"
fi

# ---------- Ping targets ----------
PING_TARGETS=("1.1.1.1" "8.8.8.8" "google.com")
PING_STATS=()

INTERNET_ONLINE="false"

for T in "${PING_TARGETS[@]}"; do
    STAT=$(get_ping_stats "$T")
    PING_STATS+=("$STAT")
    [[ "$STAT" == *"|true" ]] && INTERNET_ONLINE="true"
done

INTERNET_STATUS="OFFLINE"
[[ "$INTERNET_ONLINE" == "true" ]] && INTERNET_STATUS="ONLINE"

# ---------- DNS test ----------
DNS_STATUS="N/A"
DNS_GOOGLE_IP="N/A"

DNS_RES=$(getent ahosts google.com | awk '{print $1}' | head -n3)
if [[ -n "$DNS_RES" ]]; then
    DNS_GOOGLE_IP=$(echo "$DNS_RES" | tr '\n' ',' | sed 's/,/, /g;s/, $//')
    DNS_STATUS="OK"
else
    DNS_STATUS="ERROR"
fi

# ---------- TCP connections ----------
TCP_ESTABLISHED=$(ss -tan state established 2>/dev/null | tail -n +2 | wc -l)

# ---------- Build output ----------
{
echo "===== INTERNET MONITORING ====="
echo "Date   : $NOW"
echo "Server : $SERVER"
echo ""

echo "[ISP]"
echo "External IP     : $EXT_IP"
echo "Provider        : $ISP_NAME"
echo "Location        : $ISP_CITY, $ISP_COUNTRY"
echo ""

echo "[ROUTING]"
echo "Internet Status : $INTERNET_STATUS"
echo "Default Gateway : $GATEWAY"
echo "Route Metric    : $ROUTE_METRIC"
echo "Interface Alias : $IFACE_ALIAS"
echo "Network Profile : $PROFILE_NAME ($PROFILE_TYPE)"
echo ""

echo "[INTERNET QUALITY]"
for PS in "${PING_STATS[@]}"; do
    IFS='|' read TARGET SENT RECEIVED LOSS AVG ONLINE <<< "$PS"
    echo "Target ${TARGET,-10} : Avg ${AVG,-8} Loss $LOSS (Sent $SENT, Recv $RECEIVED)"
done
echo ""

echo "[DNS]"
echo "Resolver Status : $DNS_STATUS"
echo "google.com A    : $DNS_GOOGLE_IP"
echo ""

echo "[CONNECTIONS]"
echo "TCP Established : $TCP_ESTABLISHED"
echo ""

} > "$OUT_FILE"

echo "Monitoring report created: $OUT_FILE"
