#!/usr/bin/env bash
# ================================
# GitCloud | Linux Update Status (FULL LIST)
# ================================

set -u
set -o pipefail

OUT_DIR="/home/gitcloud/www/database/serwer-linux/updates"
OUT_FILE="$OUT_DIR/updates.txt"

mkdir -p "$OUT_DIR"

SERVER="$(hostname)"
NOW="$(date "+%Y-%m-%d %H:%M:%S")"

PKG_MANAGER="unknown"
PENDING=0
SECURITY=0
OTHER=0
UPGRADES=""

# helper: timeout wrapper
run_timeout() {
  local t="$1"; shift
  timeout "${t}s" "$@" 2>/dev/null
}

# ================================
# Detect package manager
# ================================

if command -v apt >/dev/null 2>&1; then
  PKG_MANAGER="apt"

  run_timeout 60 apt update -qq || true

  UPGRADES="$(apt list --upgradable 2>/dev/null | tail -n +2 | awk -F/ '{print $1}')"
  PENDING="$(printf "%s\n" "$UPGRADES" | sed '/^\s*$/d' | wc -l | awk '{print $1}')"

  if [[ "$PENDING" -gt 0 ]]; then
    while IFS= read -r PKG; do
      [[ -z "$PKG" ]] && continue
      if run_timeout 5 apt-cache show "$PKG" | grep -qi security; then
        SECURITY=$((SECURITY + 1))
      else
        OTHER=$((OTHER + 1))
      fi
    done <<< "$UPGRADES"
  fi

elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"

  UPGRADES="$(dnf check-update --quiet 2>/dev/null | awk 'NF==3 {print $1}')"
  PENDING="$(printf "%s\n" "$UPGRADES" | sed '/^\s*$/d' | wc -l | awk '{print $1}')"

  SECURITY="$(dnf updateinfo list security 2>/dev/null | grep -c advisory || true)"
  OTHER=$((PENDING - SECURITY))

elif command -v pacman >/dev/null 2>&1; then
  PKG_MANAGER="pacman"

  UPGRADES="$(pacman -Qu 2>/dev/null | awk '{print $1}')"
  PENDING="$(printf "%s\n" "$UPGRADES" | sed '/^\s*$/d' | wc -l | awk '{print $1}')"

  SECURITY=0
  OTHER="$PENDING"

elif command -v zypper >/dev/null 2>&1; then
  PKG_MANAGER="zypper"

  UPGRADES="$(zypper list-updates 2>/dev/null | awk 'NR>4 {print $5}')"
  PENDING="$(printf "%s\n" "$UPGRADES" | sed '/^\s*$/d' | wc -l | awk '{print $1}')"

  SECURITY="$(zypper list-patches --category security 2>/dev/null | grep -c needed || true)"
  OTHER=$((PENDING - SECURITY))
fi

# ================================
# Write output
# ================================

{
  echo "===== LINUX UPDATE STATUS ====="
  echo "Server : $SERVER"
  echo "Date   : $NOW"
  echo ""
  echo "Package Manager : $PKG_MANAGER"
  echo ""
  echo "Pending Updates : $PENDING"
  echo "Security Updates: $SECURITY"
  echo "Other Updates   : $OTHER"
  echo ""
  echo "Pending updates list:"

  if [[ "${PENDING:-0}" -eq 0 ]]; then
    echo " - No pending updates."
  else
    while IFS= read -r PKG; do
      [[ -z "$PKG" ]] && continue
      echo " - $PKG"
    done <<< "$UPGRADES"
  fi
} > "$OUT_FILE"

echo "Update status saved to: $OUT_FILE"
