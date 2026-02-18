#!/usr/bin/env bash
# ==========================================
# GitCloud | Run All Scripts (safe runner)
# ==========================================

# ----- HARD REQUIREMENTS -----
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C
export LC_ALL=C

BASE_DIR="/home/gitcloud/www/scripts/scripts"
LOG_DIR="/home/gitcloud/logs"
TIMEOUT_SEC=180

mkdir -p "$LOG_DIR"

echo "===== RUN START: $(date -u '+%Y-%m-%d %H:%M:%S UTC') ====="

# ----- sanity check -----
if [[ ! -d "$BASE_DIR" ]]; then
    echo "FATAL: scripts directory not found: $BASE_DIR"
    exit 1
fi

# ----- main loop -----
for SCRIPT in "$BASE_DIR"/*.sh; do
    NAME="$(basename "$SCRIPT")"
    LOG="$LOG_DIR/${NAME%.sh}.log"

    echo ""
    echo ">>> RUNNING: $NAME"

    if [[ ! -f "$SCRIPT" ]]; then
        echo "!!! SKIP: file not found"
        continue
    fi

    if [[ ! -x "$SCRIPT" ]]; then
        echo "!!! FIX PERMISSION: chmod +x $SCRIPT"
        chmod +x "$SCRIPT" || {
            echo "!!! FAILED TO SET EXEC BIT"
            continue
        }
    fi

    # ----- run script in controlled env -----
    timeout --kill-after=10s "${TIMEOUT_SEC}s" \
        env -i \
        PATH="$PATH" \
        LANG="$LANG" \
        LC_ALL="$LC_ALL" \
        bash "$SCRIPT" \
        >"$LOG" 2>&1

    EXIT_CODE=$?

    # ----- result handling -----
    case "$EXIT_CODE" in
        0)
            echo "✓ DONE: $NAME"
            ;;
        124)
            echo "!!! TIMEOUT: $NAME (>${TIMEOUT_SEC}s)"
            ;;
        137)
            echo "!!! KILLED: $NAME (SIGKILL / OOM / timeout kill-after)"
            ;;
        *)
            echo "!!! ERROR ($EXIT_CODE): $NAME"
            echo "    ↳ last 10 log lines:"
            tail -n 10 "$LOG" | sed 's/^/      | /'
            ;;
    esac
done

echo ""
echo "===== RUN END: $(date -u '+%Y-%m-%d %H:%M:%S UTC') ====="
