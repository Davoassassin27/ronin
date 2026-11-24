#!/usr/bin/env bash
# =============================================================================
# Ronin - guest helpers
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR="${REPO_DIR:-/root/build-scripts}"
CONFIG_FILE="${CONFIG_FILE:-$REPO_DIR/build.env}"
STATE_FILE="${STATE_FILE:-$REPO_DIR/build-state.env}"
REPORT_DIR="${REPORT_DIR:-$REPO_DIR/reports}"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_root() { [[ ${EUID} -eq 0 ]] || die "Ejecutar como root."; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Falta el comando: $1"; }
require_file() { [[ -f "$1" ]] || die "Falta el archivo: $1"; }

load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Falta $CONFIG_FILE (ejecutar .\\build.ps1 push)"
  # shellcheck disable=SC1090
  set -a
  . "$CONFIG_FILE"
  set +a

  : "${TARGET_USER:=davosoler}"
  : "${TARGET_HOSTNAME:=ronin}"
  : "${TARGET_TIMEZONE:=America/Argentina/Buenos_Aires}"
  : "${TARGET_LOCALE:=en_US.UTF-8}"
  : "${TARGET_KEYMAP:=la-latin1}"
  : "${TARGET_DISK:=/dev/vda}"
  : "${ESP_SIZE:=1G}"
  : "${ROOT_LABEL:=CACHY_ROOT}"
  : "${INSTALL_OMARCHY:=yes}"
  : "${OMARCHY_MODE:=overlay}"
  : "${OMARCHY_REF:=quattro}"
  : "${INSTALL_NVIDIA:=yes}"
  : "${INSTALL_GAMING:=yes}"
  : "${INSTALL_KENSEI:=yes}"
  : "${KENSEI_PRELOAD_MODEL:=no}"
  : "${KENSEI_REPO:=https://github.com/Davoassassin27/kensei.git}"
  : "${KENSEI_REF:=main}"
  : "${ENABLE_FIREWALL:=yes}"
  : "${OMARCHY_AUTOLOGIN:=yes}"
}

is_live() {
  [[ -d /run/archiso ]] || [[ -f /etc/cachyos-release && ! -d /run/systemd/system ]]
}

is_booted() {
  [[ -d /run/systemd/system ]]
}

require_live() {
  is_live || die "Este script debe correr en el entorno live (ISO)."
}

require_installed() {
  is_booted || die "Este script debe correr en el sistema instalado y arrancado."
}

partition_paths() {
  local disk="$1"
  mapfile -t PARTS < <(lsblk -lnpo NAME "$disk" | tail -n +2)
  [[ ${#PARTS[@]} -ge 2 ]] || die "No se detectaron 2 particiones en $disk"
}

uuid_of() {
  blkid -s UUID -o value "$1" 2>/dev/null || true
}

partlabel_of() {
  blkid -s PARTLABEL -o value "$1" 2>/dev/null || true
}

mountopts() {
  local subvol="$1"
  local extra="${2:-}"
  local opts="noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=$subvol"
  if [[ -n "$extra" ]]; then opts="$extra,$opts"; fi
  printf '%s' "$opts"
}

try_mount() {
  local dev="$1" target="$2" opts="$3"
  mkdir -p "$target"
  if mountpoint -q "$target"; then
    warn "$target ya está montado; se omite"
    return 0
  fi
  mount -o "$opts" "$dev" "$target"
}

umount_mnt() {
  if mountpoint -q /mnt; then
    umount -R /mnt || true
  fi
}

install_pkgs() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -gt 0 ]] || return 0
  log "Instalando ${#pkgs[@]} paquetes..."
  if pacman -S --needed --noconfirm "${pkgs[@]}"; then
    return 0
  fi
  warn "La instalación grupal falló; reintentando paquete por paquete..."
  local pkg failed=()
  for pkg in "${pkgs[@]}"; do
    if ! pacman -S --needed --noconfirm "$pkg"; then
      failed+=("$pkg")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    warn "Paquetes no instalados: ${failed[*]}"
    return 1
  fi
}

enable_service() {
  local svc="$1"
  systemctl enable "$svc" >/dev/null 2>&1 || { warn "No se pudo habilitar $svc"; return 1; }
  log "Habilitado: $svc"
}

restart_if_booted() {
  local svc="$1"
  if is_booted; then
    systemctl restart "$svc" >/dev/null 2>&1 || warn "No se pudo reiniciar $svc"
  fi
}

write_state() {
  local key="$1" value="$2"
  touch "$STATE_FILE"
  if grep -q "^${key}=" "$STATE_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$STATE_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$STATE_FILE"
  fi
}

read_state() {
  local key="$1" default="${2:-}"
  if [[ -f "$STATE_FILE" ]]; then
    local line
    line=$(grep -m1 "^${key}=" "$STATE_FILE" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  fi
  printf '%s' "$default"
}

require_confirm() {
  local expected="$1" message="$2"
  if [[ "${CONFIRM_WIPE:-}" == "$expected" ]]; then
    log "Confirmación por variable CONFIRM_WIPE=$expected"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "$message. Reejecutar con CONFIRM_WIPE=$expected"
  fi
  printf '%s\n' "$message"
  read -r -p "Escribir '$expected' para continuar: " answer
  [[ "$answer" == "$expected" ]] || die "Confirmación incorrecta."
}

make_report_dir() {
  mkdir -p "$REPORT_DIR"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

timestamp() {
  date --iso-8601=seconds
}

# ---------------------------------------------------------------------------
# Trazabilidad UX: todo fallo de montaje/uso se registra en JSONL.
# UX_LOG_FILE se puede sobrescribir en los tests para no tocar /var/log.
# ---------------------------------------------------------------------------
UX_LOG_FILE="${UX_LOG_FILE:-/var/log/ronin/ux-trace.jsonl}"

ux_log() {
  local level="$1" component="$2" message="$3" context="${4:-}" code="${5:-0}"
  local ts dir
  ts=$(date --iso-8601=seconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  dir=$(dirname "$UX_LOG_FILE")
  mkdir -p "$dir" 2>/dev/null || true
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$ts" --arg level "$level" --arg component "$component" \
      --arg message "$message" --arg context "$context" --argjson code "$code" \
      '{ts:$ts,level:$level,component:$component,message:$message,context:$context,code:$code}' \
      >> "$UX_LOG_FILE" 2>/dev/null || true
  else
    printf '{"ts":"%s","level":"%s","component":"%s","message":"%s","context":"%s","code":%s}\n' \
      "$ts" "$level" "$component" "$message" "$context" "$code" >> "$UX_LOG_FILE" 2>/dev/null || true
  fi
}

ux_fail() {
  local component="$1" message="$2" context="${3:-}" code="${4:-1}"
  ux_log fail "$component" "$message" "$context" "$code"
  warn "UX-FAIL [$component] $message"
  return "$code"
}

# Ejecuta un comando y registra pass/fail con su salida. Útil para montajes.
ux_run() {
  local component="$1" desc="$2"; shift 2
  local out rc=0
  if out=$("$@" 2>&1); then
    ux_log pass "$component" "$desc" "ok" 0
  else
    rc=$?
    ux_log fail "$component" "$desc" "$(printf '%s' "$out" | tail -n1)" "$rc"
  fi
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# Detección de disco: la verificación debe funcionar igual en la imagen de
# build (/dev/vda, 2 particiones) y en el NVMe final (/dev/nvme0n1, 3).
# ---------------------------------------------------------------------------
root_source() {
  local src
  src=$(findmnt -no SOURCE / 2>/dev/null | head -n1) || return 1
  [[ -n "$src" ]] || return 1
  printf '%s\n' "${src%%\[*}"
}

disk_of() {
  local dev="$1" pk
  pk=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1) || return 1
  [[ -n "$pk" ]] || return 1
  printf '/dev/%s\n' "$pk"
}

detect_disk_layout() {
  local src disk parts count first_type
  src=$(root_source) || return 1
  disk=$(disk_of "$src") || return 1
  parts=$(lsblk -lnpo NAME "$disk" 2>/dev/null | tail -n +2) || return 1
  count=$(printf '%s\n' "$parts" | grep -c . || true)

  DETECT_DISK="$disk"
  DETECT_ROOT_DEV="$src"
  DETECT_PART_COUNT="$count"
  DETECT_DATA_DEV=""
  DETECT_ESP_DEV=""
  DETECT_ROOT_DISK_DEV=""
  DETECT_LAYOUT=build

  if (( count >= 3 )); then
    DETECT_DATA_DEV=$(printf '%s\n' "$parts" | sed -n '1p')
    DETECT_ESP_DEV=$(printf '%s\n' "$parts" | sed -n '2p')
    DETECT_ROOT_DISK_DEV=$(printf '%s\n' "$parts" | sed -n '3p')
    first_type=$(blkid -s TYPE -o value "$DETECT_DATA_DEV" 2>/dev/null || true)
    if [[ "$first_type" == "exfat" ]]; then
      DETECT_LAYOUT=migrated
    fi
  else
    DETECT_ESP_DEV=$(printf '%s\n' "$parts" | sed -n '1p')
    DETECT_ROOT_DISK_DEV=$(printf '%s\n' "$parts" | sed -n '2p')
  fi

  export DETECT_DISK DETECT_ROOT_DEV DETECT_PART_COUNT DETECT_LAYOUT \
    DETECT_DATA_DEV DETECT_ESP_DEV DETECT_ROOT_DISK_DEV
}

# Habilita los repos CachyOS (x86-64-v3) en el sistema instalado.
# Idempotente: no duplica el bloque si ya existe.
configure_cachyos_repos() {
  local conf=/etc/pacman.conf
  local mirror=/etc/pacman.d/cachyos-mirrorlist
  local v3mirror=/etc/pacman.d/cachyos-v3-mirrorlist

  [[ -f "$mirror" ]] || { warn "Falta $mirror"; return 1; }

  if grep -q '^\[cachyos-v3\]' "$conf"; then
    log "Repos CachyOS ya configurados"
    return 0
  fi

  if ! /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3 (supported'; then
    warn "CPU sin soporte x86-64-v3; se omite el repo optimizado"
    return 0
  fi

  sed 's|\$arch|x86_64_v3|g' "$mirror" > "$v3mirror"

  local block
  block=$(mktemp)
  cat > "$block" <<'EOF'
# Ronin - repos CachyOS optimizados x86-64-v3
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF

  awk -v blockfile="$block" '
    BEGIN { while ((getline line < blockfile) > 0) blk = blk line "\n" }
    /^\[core\]/ && !done { printf "%s", blk; done=1 }
    { print }
  ' "$conf" > "$conf.new"
  mv "$conf.new" "$conf"
  rm -f "$block"

  log "Repos CachyOS x86-64-v3 habilitados"
}
