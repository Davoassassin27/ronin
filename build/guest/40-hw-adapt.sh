#!/usr/bin/env bash
# =============================================================================
# F1.6 - Instalar y probar hw-adapt
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/hw-adapt-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Instalando hw-adapt"

install -Dm755 "$REPO_DIR/config/usr/local/bin/hw-adapt.sh" /usr/local/bin/hw-adapt.sh
install -Dm644 "$REPO_DIR/config/etc/systemd/system/hw-adapt.service" /etc/systemd/system/hw-adapt.service
sed "s|@TARGET_USER@|$TARGET_USER|g" "$REPO_DIR/config/etc/hw-adapt.conf" > /etc/hw-adapt.conf
chmod 644 /etc/hw-adapt.conf
install -Dm644 "$REPO_DIR/config/etc/profile.d/ai-gpu-env.sh" /etc/profile.d/ai-gpu-env.sh

systemctl daemon-reload
systemctl enable hw-adapt.service >/dev/null
log "hw-adapt habilitado"

# --- Pruebas aisladas --------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_test() {
  local name="$1"; shift
  local out="$TMP/$name.json"
  if env HW_ADAPT_DRY_RUN=1 \
      HW_ADAPT_STATE_DIR="$TMP/$name-state" \
      HW_ADAPT_LOG_FILE="$TMP/$name.log" \
      HW_ADAPT_JSON_FILE="$out" \
      HW_ADAPT_ENV_FILE="$TMP/$name.env" \
      HW_ADAPT_HYPR_FILE="$TMP/$name-hypr.conf" \
      "$@" /usr/local/bin/hw-adapt.sh >/dev/null 2>&1; then
    jq -e . "$out" >/dev/null || die "JSON inválido en test $name"
    log "OK test $name: $(jq -c '{mode,profile,gpus:(.gpus|length),changed_board}' "$out")"
  else
    die "Falló el test $name"
  fi
}

run_test desktop env HW_ADAPT_FAKE_BATTERY=0
run_test laptop env HW_ADAPT_FAKE_BATTERY=1 HW_ADAPT_FAKE_AC=0

# Cambio de placa: sembrar estado previo distinto
mkdir -p "$TMP/board-state"
jq -n '{board:"OLD_BOARD",product:"OLD_PRODUCT"}' > "$TMP/board-state/state.json"
OUT="$TMP/board-change.json"
env HW_ADAPT_DRY_RUN=1 HW_ADAPT_FAKE_BOARD="NEW_BOARD" \
  HW_ADAPT_STATE_DIR="$TMP/board-state" \
  HW_ADAPT_LOG_FILE="$TMP/board.log" \
  HW_ADAPT_JSON_FILE="$OUT" \
  HW_ADAPT_ENV_FILE="$TMP/board.env" \
  HW_ADAPT_HYPR_FILE="$TMP/board-hypr.conf" \
  /usr/local/bin/hw-adapt.sh >/dev/null
[[ "$(jq -r .changed_board "$OUT")" == "true" ]] || die "No se detectó cambio de placa"
log "OK cambio de placa detectado"

# --- Ejecución real ----------------------------------------------------------
systemctl start hw-adapt.service
systemctl is-active --quiet hw-adapt.service || die "hw-adapt no quedó activo"

jq -e '.schema == 1 and .board != null and .cpu != null and (.gpus|type=="array")' /var/log/hw-adapt-last.json >/dev/null \
  || die "JSON de producción inválido"

bash -n /etc/profile.d/ai-gpu-env.sh || die "ai-gpu-env.sh inválido"

log "Perfil aplicado: $(jq -r '.profile' /var/log/hw-adapt-last.json)"
log "Modo: $(jq -r '.mode' /var/log/hw-adapt-last.json)"
log "GPUs: $(jq -c '.gpus' /var/log/hw-adapt-last.json)"
log "HW-ADAPT OK"
