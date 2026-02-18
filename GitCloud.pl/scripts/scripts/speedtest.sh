#!/usr/bin/env bash
set -euo pipefail

DIR="/home/gitcloud/www/database/serwer-linux/monitoring"
FILE="${DIR}/speedtest.txt"

mkdir -p "$DIR"

# Select available speedtest command (portable)
pick_speedtest_cmd() {
  # Preferred: Ookla speedtest
  if command -v speedtest >/dev/null 2>&1; then
    local help
    help="$(speedtest -h 2>&1 || true)"

    if grep -q -- '--accept-license' <<<"$help"; then
      if grep -q -- '--accept-gdpr' <<<"$help"; then
        echo "speedtest --accept-license --accept-gdpr"
      else
        echo "speedtest --accept-license"
      fi
    else
      echo "yes | speedtest"
    fi
    return 0
  fi

  # Python speedtest-cli
  if command -v speedtest-cli >/dev/null 2>&1; then
    echo "speedtest-cli --simple"
    return 0
  fi

  # Python module fallback
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import speedtest" >/dev/null 2>&1; then
      echo "python3 -m speedtest"
      return 0
    fi
  fi

  return 1
}

CMD="$(pick_speedtest_cmd || true)"
if [[ -z "$CMD" ]]; then
  echo "ERROR: speedtest not found" >&2
  exit 1
fi

{
  echo "===== SPEEDTEST REPORT ====="
  echo "Host: $(hostname)"
  echo "Date: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "Command: ${CMD}"
  echo
  bash -lc "${CMD}"
  echo
  echo "===== END ====="
} > "$FILE"

echo "Saved: $FILE"
