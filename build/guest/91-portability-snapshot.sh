#!/usr/bin/env bash
# =============================================================================
# Ronin - Evidencia de portabilidad antes de mover el NVMe a otra maquina
# =============================================================================
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Ejecutar con sudo" >&2; exit 1; }

BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)
STAMP=$(date +%Y%m%d-%H%M%S)
HW_JSON="/var/log/hw-adapt-${STAMP}-${BOARD}.json"
VERIFY_JSON="/var/log/ronin-verify-${STAMP}-${BOARD}.json"

install -m 644 /var/log/hw-adapt-last.json "$HW_JSON"

if [[ -x /root/build-scripts/guest/90-verify.sh ]]; then
  bash /root/build-scripts/guest/90-verify.sh || true
  if [[ -f /var/log/ronin-verify.json ]]; then
    install -m 644 /var/log/ronin-verify.json "$VERIFY_JSON"
  fi
fi

echo "Board:    $BOARD"
echo "hw-adapt: $HW_JSON"
if [[ -f $VERIFY_JSON ]]; then
  echo "verify:   $VERIFY_JSON"
fi
if command -v jq >/dev/null 2>&1; then
  jq -c '{board,product,mode,profile,changed_board,gpus:[.gpus[].vendor]}' "$HW_JSON" 2>/dev/null || true
fi
