#!/bin/bash
# ================================
# GitCloud | Virtual Network Info
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/vpn"
OUT_FILE="$OUT_DIR/siec.txt"

mkdir -p "$OUT_DIR"

DATE=$(date "+%Y-%m-%d %H:%M:%S")

# Detect virtual / VPN interfaces
ADAPTERS=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ei 'tun|tap|wg|zt|tailscale|vmnet|veth|br-|docker|virbr')

COUNT=$(echo "$ADAPTERS" | grep -c .)

{
echo "===== VIRTUAL / VPN NETWORK ADAPTERS ====="
echo "Generated: $DATE"
echo "Total adapters: $COUNT"
echo ""

for IFACE in $ADAPTERS; do

    STATUS=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo "unknown")
    MAC=$(cat /sys/class/net/$IFACE/address 2>/dev/null || echo "none")

    SPEED=$(cat /sys/class/net/$IFACE/speed 2>/dev/null)
    [[ -z "$SPEED" ]] && SPEED="unknown" || SPEED="${SPEED}Mb/s"

    IFINDEX=$(cat /sys/class/net/$IFACE/ifindex 2>/dev/null || echo "n/a")

    IPV4=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}')
    GW=$(ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3}')

    echo "----------------------------------------"
    echo "Name        : $IFACE"
    echo "Description : Virtual / VPN Interface"
    echo "Status      : $STATUS"
    echo "MAC         : $MAC"
    echo "Link Speed  : $SPEED"
    echo "ifIndex     : $IFINDEX"

    if [[ -n "$IPV4" ]]; then
        for IP in $IPV4; do
            echo "IPv4        : $IP"
        done
    else
        echo "IPv4        : none"
    fi

    if [[ -n "$GW" ]]; then
        echo "Gateway     : $GW"
    else
        echo "Gateway     : none"
    fi

    echo ""
done

echo "===== END OF REPORT ====="
} > "$OUT_FILE"

echo "VPN / Virtual network report saved to $OUT_FILE"
