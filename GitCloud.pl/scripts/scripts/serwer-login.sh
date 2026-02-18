#!/bin/bash
# ================================
# GitCloud | Server Login Report
# ================================

OUT_DIR="/home/gitcloud/www/database/serwer-linux/login"
OUT_FILE="$OUT_DIR/serwer-login.txt"

mkdir -p "$OUT_DIR"

SERVER=$(hostname)
NOW=$(date "+%Y-%m-%d %H:%M:%S")

# Получаем активные сессии
SESSIONS=$(who)

# Если сессий нет
if [[ -z "$SESSIONS" ]]; then
    echo "Нет активных пользовательских сессий." > "$OUT_FILE"
    cat "$OUT_FILE"
    exit 0
fi

{
echo "===== LOCAL SERVER LOGIN REPORT ====="
echo "Server: $SERVER"
echo "Generated: $NOW"
echo ""
echo "Active Logons:"
echo ""

while read -r line; do
    # who format:
    # user tty  YYYY-MM-DD HH:MM (IP)
    USERNAME=$(echo "$line" | awk '{print $1}')
    SESSION=$(echo "$line"  | awk '{print $2}')
    LOGON_TIME=$(echo "$line" | awk '{print $3, $4}')
    ID="N/A"
    STATE="Active"

    echo "User: $USERNAME"
    echo "Session: $SESSION"
    echo "ID: $ID"
    echo "State: $STATE"
    echo "Logon Time: $LOGON_TIME"
    echo ""

done <<< "$SESSIONS"

} > "$OUT_FILE"

# Дублируем в консоль
cat "$OUT_FILE"
