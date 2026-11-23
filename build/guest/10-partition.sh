#!/usr/bin/env bash
# =============================================================================
# F1.2 - GPT + Btrfs + subvolúmenes
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_live
load_config
make_report_dir

DISK="${TARGET_DISK_OVERRIDE:-$TARGET_DISK}"
[[ -b "$DISK" ]] || die "$DISK no existe"

LOG="$REPORT_DIR/partition-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Particionando $DISK"
require_confirm YES "Se va a borrar TODO en $DISK"

umount_mnt
swapoff -a 2>/dev/null || true
wipefs -a "$DISK" || true
sgdisk --zap-all "$DISK"
partprobe "$DISK" || true
udevadm settle

sgdisk \
  -n "1:0:+${ESP_SIZE}" -t 1:ef00 -c 1:ESP \
  -n "2:0:0"           -t 2:8300 -c 2:"$ROOT_LABEL" \
  "$DISK"
partprobe "$DISK"
udevadm settle

partition_paths "$DISK"
ESP="${PARTS[0]}"
ROOT="${PARTS[1]}"
[[ -b "$ESP" && -b "$ROOT" ]] || die "No se pudieron resolver las particiones de $DISK"

log "ESP:  $ESP"
log "ROOT: $ROOT"

mkfs.fat -F32 -n ESP "$ESP"
mkfs.btrfs -f -L "$ROOT_LABEL" "$ROOT"

BASE_OPTS="noatime,compress=zstd:3,ssd,discard=async,space_cache=v2"
ROOT_OPTS="$BASE_OPTS,subvol=@"
# Las opciones de btrfs son por superbloque, no por subvolumen. El aislamiento
# de Docker se hace con chattr +C en el directorio (nodatacow heredado).
DOCKER_OPTS="$BASE_OPTS,subvol=@docker"

# Montaje temporal para crear subvolúmenes
mkdir -p /mnt
mount -o "$BASE_OPTS" "$ROOT" /mnt

for sv in @ @home @var_cache @var_log @docker @snapshots; do
  btrfs subvolume create "/mnt/$sv"
done

umount /mnt
mount -o "$ROOT_OPTS" "$ROOT" /mnt

mkdir -p /mnt/boot /mnt/home /mnt/var/cache /mnt/var/log /mnt/var/lib/docker /mnt/.snapshots

mount -o "$BASE_OPTS,subvol=@home"       "$ROOT" /mnt/home
mount -o "$BASE_OPTS,subvol=@var_cache"  "$ROOT" /mnt/var/cache
mount -o "$BASE_OPTS,subvol=@var_log"    "$ROOT" /mnt/var/log
mount -o "$DOCKER_OPTS"                  "$ROOT" /mnt/var/lib/docker
mount -o "$BASE_OPTS,subvol=@snapshots"  "$ROOT" /mnt/.snapshots
mount "$ESP" /mnt/boot

# nodatacow por inodo/subárbol: debe aplicarse antes de que Docker escriba.
if chattr +C /mnt/var/lib/docker 2>/dev/null; then
  log "chattr +C aplicado a /var/lib/docker: $(lsattr -d /mnt/var/lib/docker | awk '{print $1}')"
else
  warn "chattr +C falló en /var/lib/docker; Docker podría degradar I/O"
fi

ROOT_UUID=$(uuid_of "$ROOT")
ESP_UUID=$(uuid_of "$ESP")
[[ -n "$ROOT_UUID" && -n "$ESP_UUID" ]] || die "No se pudieron leer los UUID"

write_state TARGET_DISK "$DISK"
write_state ESP_PART "$ESP"
write_state ROOT_PART "$ROOT"
write_state ROOT_UUID "$ROOT_UUID"
write_state ESP_UUID "$ESP_UUID"
write_state ROOT_LABEL "$ROOT_LABEL"

sync
log "UUID root: $ROOT_UUID"
log "UUID ESP:  $ESP_UUID"
log "Layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS | sed 's/^/    /'
log "Subvolúmenes:"
btrfs subvolume list /mnt | sed 's/^/    /'
log "Montajes:"
findmnt -R /mnt | sed 's/^/    /'

log "PARTITION OK"
log "Siguiente: bash $SCRIPT_DIR/20-bootstrap.sh"
