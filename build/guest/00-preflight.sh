#!/usr/bin/env bash
# =============================================================================
# F1.0 - Preflight del entorno live
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
load_config
make_report_dir

DISK="${TARGET_DISK_OVERRIDE:-$TARGET_DISK}"
LOG="$REPORT_DIR/preflight-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Ronin preflight"
log "Repo: $REPO_DIR"
log "Disco objetivo: $DISK"
log "Fecha: $(timestamp)"

fail=0
check() {
  local name="$1"; shift
  if "$@"; then
    log "OK   $name"
  else
    warn "FAIL $name"
    fail=$((fail + 1))
  fi
}

# --- UEFI --------------------------------------------------------------------
check "UEFI activo" test -d /sys/firmware/efi
check "x86_64" test "$(uname -m)" = "x86_64"

if /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3 (supported'; then
  log "OK   CPU soporta x86-64-v3"
else
  warn "FAIL CPU no reporta x86-64-v3; CachyOS v3 no es seguro en este equipo"
  fail=$((fail + 1))
fi

# --- Herramientas ------------------------------------------------------------
for cmd in sgdisk mkfs.btrfs mkfs.fat pacstrap arch-chroot blkid lsblk findmnt curl jq; do
  check "comando $cmd" command -v "$cmd" >/dev/null
done

log "Sincronizando índices de pacman del live..."
pacman -Sy --noconfirm >/dev/null 2>&1 || warn "pacman -Sy falló"

# --- ISO / repos -------------------------------------------------------------
if [[ -f /etc/cachyos-release ]]; then
  log "OK   Entorno CachyOS: $(tr '\n' ' ' < /etc/cachyos-release)"
else
  warn "WARN No se detecta /etc/cachyos-release; ¿es la ISO correcta?"
fi

if pacman -Si linux-cachyos >/dev/null 2>&1; then
  log "OK   repo linux-cachyos disponible"
else
  warn "FAIL linux-cachyos no disponible en los repos del live"
  fail=$((fail + 1))
fi

# --- Red / hora --------------------------------------------------------------
if curl -fsS --max-time 10 https://mirror.cachyos.org/ >/dev/null 2>&1; then
  log "OK   conectividad a mirror.cachyos.org"
else
  warn "FAIL sin conectividad al mirror de CachyOS"
  fail=$((fail + 1))
fi

if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
  log "OK   reloj sincronizado"
else
  warn "WARN reloj no sincronizado; los paquetes pueden fallar por firmas"
fi

# --- Disco -------------------------------------------------------------------
[[ -b "$DISK" ]] || die "$DISK no es un dispositivo de bloque"
check "disco $DISK existe" test -b "$DISK"

SIZE_BYTES=$(blockdev --getsize64 "$DISK" 2>/dev/null || echo 0)
if (( SIZE_BYTES > 100 * 1024 * 1024 * 1024 )); then
  log "OK   tamaño del disco: $((SIZE_BYTES / 1024 / 1024 / 1024)) GiB"
else
  warn "FAIL disco demasiado chico: $SIZE_BYTES bytes"
  fail=$((fail + 1))
fi

LIVE_SRC=$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)
if [[ -n "$LIVE_SRC" ]] && [[ "$(lsblk -no PKNAME "$LIVE_SRC" 2>/dev/null)" == "$(basename "$DISK")" ]]; then
  warn "FAIL $DISK contiene el medio live; elegir otro disco"
  fail=$((fail + 1))
fi

if findmnt -S "$DISK" >/dev/null 2>&1; then
  warn "FAIL $DISK está montado; desmontar antes de continuar"
  fail=$((fail + 1))
fi

if lsblk -lnpo NAME "$DISK" | tail -n +2 | grep -q .; then
  warn "El disco ya tiene particiones; se borrarán."
  require_confirm YES "Se va a borrar TODO en $DISK"
else
  log "OK   disco vacío (sin particiones)"
fi

# --- Resumen -----------------------------------------------------------------
log "Discos visibles:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL | sed 's/^/    /'

if (( fail > 0 )); then
  die "Preflight falló con $fail error(es). Revisar $LOG"
fi

log "PREFLIGHT OK"
log "Reporte: $LOG"
log "Siguiente: CONFIRM_WIPE=YES bash $SCRIPT_DIR/10-partition.sh"
