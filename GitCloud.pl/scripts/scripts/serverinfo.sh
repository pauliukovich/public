#!/bin/bash
# ==========================================
# GitCloud | Server Hardware & OS Inventory
# ==========================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/drive"
OUT_FILE="$OUT_DIR/serverdrive.txt"

mkdir -p "$OUT_DIR"

NOW=$(date "+%Y-%m-%d %H:%M:%S")
SERVER=$(hostname)

{
echo "===== SERVER INVENTORY ====="
echo "Date   : $NOW"
echo "Server : $SERVER"
echo ""

# =========================
# OPERATING SYSTEM / DOMAIN
# =========================
echo "[OPERATING SYSTEM]"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Caption      : $NAME"
    echo "Version      : $VERSION"
else
    echo "Caption      : Unknown"
    echo "Version      : Unknown"
fi
echo "Build Number : $(uname -r)"
echo "Architecture : $(uname -m)"
echo "Install Date : $(stat -c %y / | cut -d'.' -f1)"
echo ""

echo "[DOMAIN]"
DOMAIN=$(hostname -d)
echo "Domain       : ${DOMAIN:-N/A}"
echo "Domain Role  : Linux Server"
echo "Workgroup    : N/A"
echo ""

# ==========
# CPU
# ==========
CPU_INDEX=0
lscpu | awk -F: '
/^Socket\(s\)/ {sockets=$2}
/^Model name/ {model=$2}
/^Vendor ID/ {vendor=$2}
/^CPU\(s\)/ {threads=$2}
/^Core\(s\) per socket/ {cores=$2}
/^CPU max MHz/ {maxmhz=$2}
/^CPU MHz/ {curmhz=$2}
END {
    print sockets "|" model "|" vendor "|" cores "|" threads "|" maxmhz "|" curmhz
}' | while IFS='|' read SOCKETS MODEL VENDOR CORES THREADS MAXMHZ CURMHZ; do
    ((CPU_INDEX++))
    echo "[CPU - CPU$CPU_INDEX]"
    echo "Name                  : ${MODEL# }"
    echo "Manufacturer          : ${VENDOR# }"
    echo "Description           : Processor"
    echo "Socket                : CPU$CPU_INDEX"
    echo "Cores                 : ${CORES# }"
    echo "Logical Processors    : ${THREADS# }"
    echo "Max Clock Speed (MHz) : ${MAXMHZ# }"
    echo "Current Clock (MHz)   : ${CURMHZ# }"
    echo "L2 Cache (KB)         : $(lscpu | awk '/L2 cache/ {print $3}')"
    echo "L3 Cache (KB)         : $(lscpu | awk '/L3 cache/ {print $3}')"
    echo "Processor Id          : N/A"
    echo ""
done

# ==========
# RAM
# ==========
TOTAL_RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
USED_RAM_GB=$(free -g | awk '/Mem:/ {print $3}')
FREE_RAM_GB=$(free -g | awk '/Mem:/ {print $4}')
USED_PCT=$(awk "BEGIN { printf \"%.1f\", ($USED_RAM_GB/$TOTAL_RAM_GB)*100 }")

echo "[RAM - SUMMARY]"
echo "Total Physical (GB)   : $TOTAL_RAM_GB"
echo "Total Visible (GB)    : $TOTAL_RAM_GB"
echo "Used (GB)             : $USED_RAM_GB"
echo "Free (GB)             : $FREE_RAM_GB"
echo "Used (%)              : $USED_PCT"
echo ""

if command -v dmidecode >/dev/null 2>&1; then
    INDEX=0
    dmidecode -t memory | awk '
    /^Memory Device$/ {inblock=1; next}
    inblock && /^$/ {print "---"; inblock=0}
    inblock {print}
    ' | while read -r line; do
        [[ "$line" == "---" ]] && continue
        if [[ "$line" =~ Size: ]]; then
            ((INDEX++))
            echo "[RAM MODULE #$INDEX]"
        fi
        echo "$line"
    done
    echo ""
fi

# ==========
# DISKS
# ==========
lsblk -ndo NAME,MODEL,SIZE,TYPE | awk '$4=="disk"' | while read DEV MODEL SIZE TYPE; do
    echo "[PHYSICAL DISK - /dev/$DEV]"
    echo "Model            : $MODEL"
    echo "Manufacturer     : N/A"
    echo "Serial Number    : $(udevadm info --query=property --name=/dev/$DEV | grep ID_SERIAL= | cut -d= -f2)"
    echo "Interface Type   : N/A"
    echo "Media Type       : N/A"
    echo "Firmware         : N/A"
    echo "Size (GB)        : $SIZE"
    echo ""
done

echo "[LOGICAL DISKS]"
df -h --output=source,target,fstype,size,used,avail,pcent | tail -n +2 | while read SRC MOUNT FS SIZE USED FREE PCT; do
    echo "Drive            : $SRC"
    echo "Label            : $MOUNT"
    echo "File System      : $FS"
    echo "Size (GB)        : $SIZE"
    echo "Used (GB)        : $USED"
    echo "Free (GB)        : $FREE"
    echo "Used (%)         : ${PCT%\%}"
    echo ""
done

# ==========
# NETWORK
# ==========
echo "[NETWORK ADAPTERS]"
ip -o link show | awk -F': ' '{print $2}' | while read IFACE; do
    [[ "$IFACE" == "lo" ]] && continue
    STATE=$(cat /sys/class/net/$IFACE/operstate)
    [[ "$STATE" != "up" ]] && continue

    echo "Adapter Name     : $IFACE"
    echo "Description      : $(ethtool -i $IFACE 2>/dev/null | awk '/driver/ {print $2}')"
    echo "MAC Address      : $(cat /sys/class/net/$IFACE/address)"

    SPEED=$(ethtool $IFACE 2>/dev/null | awk -F': ' '/Speed/ {print $2}')
    [[ -n "$SPEED" ]] && echo "Link Speed Raw   : $SPEED"

    ip -4 addr show $IFACE | awk '/inet / {print "IPv4 Address     : "$2}'
    ip -6 addr show $IFACE | awk '/inet6 / {print "IPv6 Address     : "$2}'

    DNS=$(resolvectl dns $IFACE 2>/dev/null | awk '{print $2}')
    [[ -n "$DNS" ]] && echo "DNS Servers      : $DNS"

    echo ""
done

} > "$OUT_FILE"

echo "Inventory saved to: $OUT_FILE"
