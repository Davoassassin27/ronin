#!/usr/bin/env bash
# =============================================================================
# F7 - Migración de la imagen al NVMe final (dry-run por defecto)
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
load_config

# Trazabilidad UX: montajes fallidos y errores de migración quedan registrados.
trap 'ux_log fail migrate "error durante la migracion" "$BASH_COMMAND" $? >/dev/null 2>&1 || true' ERR

TARGET=""
SOURCE_DISK=""
SOURCE_ESP=""
SOURCE_ROOT=""
DRY_RUN=1
ASSUME_YES=0
DO_CHECK=0

usage() {
  cat <<EOF
Uso: $0 --target /dev/nvme0n1 [opciones]

Opciones:
  --target DEV        Disco destino (obligatorio)
  --source-disk DEV   Disco origen (default: detectado desde /)
  --source-esp DEV    Partición ESP origen (default: /boot)
  --source-root DEV   Partición root origen (default: /)
  --yes               Ejecutar (sin esto es dry-run)
  --check             Ejecutar btrfs check --readonly (lento)
  -h, --help          Esta ayuda

Variables:
  CONFIRM_MIGRATE=YES   Confirmación no interactiva (además de --yes)
  NVME_DATA_SIZE        Tamaño de DATOS (default: build.env, 500G)
  NVME_ESP_SIZE         Tamaño de ESP (default: 1G)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --source-disk) SOURCE_DISK="${2:-}"; shift 2 ;;
    --source-esp) SOURCE_ESP="${2:-}"; shift 2 ;;
    --source-root) SOURCE_ROOT="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --check) DO_CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

[[ -n "$TARGET" && -b "$TARGET" ]] || die "Falta --target o no es un bloque: $TARGET"
if [[ -z "$SOURCE_ROOT" ]]; then
  SOURCE_ROOT=$(findmnt -no SOURCE /)
  SOURCE_ROOT="${SOURCE_ROOT%%[*}"
fi
if [[ -z "$SOURCE_ESP" ]]; then
  SOURCE_ESP=$(findmnt -no SOURCE /boot)
  SOURCE_ESP="${SOURCE_ESP%%[*}"
fi
if [[ -z "$SOURCE_DISK" ]]; then
  SOURCE_DISK="/dev/$(lsblk -no PKNAME "$SOURCE_ROOT" | head -n1)"
fi

[[ -b "$SOURCE_ROOT" ]] || die "Origen root inválido: $SOURCE_ROOT"
[[ -b "$SOURCE_ESP" ]] || die "Origen ESP inválido: $SOURCE_ESP"
[[ -b "$SOURCE_DISK" ]] || die "Origen disco inválido: $SOURCE_DISK"

SRC_ROOT_UUID=$(blkid -s UUID -o value "$SOURCE_ROOT" || true)
SRC_ESP_UUID=$(blkid -s UUID -o value "$SOURCE_ESP" || true)
[[ -n "$SRC_ROOT_UUID" && -n "$SRC_ESP_UUID" ]] || die "No se pudieron leer UUIDs del origen"

# Seguridad: no permitir target == source disk
if [[ "$(basename "$TARGET")" == "$(basename "$SOURCE_DISK")" ]]; then
  die "El destino es el mismo disco que el origen ($TARGET)."
fi

# No escribir sobre discos montados
if findmnt -S "$TARGET" >/dev/null 2>&1; then
  die "$TARGET está montado; desmontar antes."
fi
if lsblk -lnpo MOUNTPOINTS "$TARGET" 2>/dev/null | grep -q .; then
  die "Hay particiones de $TARGET montadas; desmontar antes."
fi

TARGET_SIZE=$(blockdev --getsize64 "$TARGET")
SOURCE_SIZE=$(blockdev --getsize64 "$SOURCE_ROOT")
if (( TARGET_SIZE < SOURCE_SIZE + 1024*1024*1024 )); then
  die "El destino ($TARGET_SIZE bytes) no es más grande que el origen ($SOURCE_SIZE bytes)."
fi

DATA_SIZE="${NVME_DATA_SIZE:-500G}"
ESP_SIZE="${NVME_ESP_SIZE:-1G}"
TARGET_MODEL=$(lsblk -dno MODEL "$TARGET" 2>/dev/null | sed 's/[[:space:]]*$//' || true)
TARGET_SERIAL=$(lsblk -dno SERIAL "$TARGET" 2>/dev/null | sed 's/[[:space:]]*$//' || true)
[[ -n "$TARGET_MODEL" ]] || TARGET_MODEL="desconocido"

# Sufijo de partición (nvme/mmc usan p)
SUFFIX=""
if [[ "$TARGET" =~ [0-9]$ ]]; then SUFFIX="p"; fi
P1="${TARGET}${SUFFIX}1"
P2="${TARGET}${SUFFIX}2"
P3="${TARGET}${SUFFIX}3"

cat <<EOF

============================================================
Ronin - migración a NVMe
============================================================
Origen:
  disco:  $SOURCE_DISK
  ESP:    $SOURCE_ESP  UUID=$SRC_ESP_UUID
  root:   $SOURCE_ROOT UUID=$SRC_ROOT_UUID
Destino:
  disco:  $TARGET
  modelo: $TARGET_MODEL
  serial: ${TARGET_SERIAL:-n/a}
  tamaño: $((TARGET_SIZE / 1024 / 1024 / 1024)) GiB
Tabla final:
  1 DATOS  exFAT  $DATA_SIZE   -> $P1
  2 ESP    FAT32  $ESP_SIZE    -> $P2
  3 ROOT   Btrfs  resto        -> $P3
============================================================
EOF

if (( DRY_RUN == 1 && ASSUME_YES == 0 )); then
  echo "DRY-RUN: no se escribió nada."
  echo "Para ejecutar: $0 --target $TARGET --yes"
  exit 0
fi

# Confirmación
if [[ "${CONFIRM_MIGRATE:-}" != "YES" ]]; then
  if [[ ! -t 0 ]]; then
    die "Confirmación requerida: CONFIRM_MIGRATE=YES $0 --target $TARGET --yes"
  fi
  echo "Se va a BORRAR $TARGET ($TARGET_MODEL)."
  read -r -p "Escribir el modelo exacto ('$TARGET_MODEL') para continuar: " answer
  [[ "$answer" == "$TARGET_MODEL" ]] || die "Confirmación incorrecta."
fi

ux_log info migrate "migracion confirmada" "target=$TARGET model=$TARGET_MODEL esp=$ESP_SIZE datos=$DATA_SIZE" 0
log "Creando GPT final en $TARGET..."
wipefs -a "$TARGET" || true
sgdisk --zap-all "$TARGET"
sgdisk \
  -n "1:0:+${DATA_SIZE}" -t 1:0700 -c 1:DATOS \
  -n "2:0:+${ESP_SIZE}"  -t 2:ef00 -c 2:ESP \
  -n "3:0:0"             -t 3:8300 -c 3:CACHY_ROOT \
  "$TARGET"
partprobe "$TARGET" || true
udevadm settle

[[ -b "$P1" && -b "$P2" && -b "$P3" ]] || die "No se crearon las particiones esperadas"

log "Formateando DATOS..."
mkfs.exfat -n DATOS "$P1"

log "Copiando ESP ($SOURCE_ESP -> $P2)..."
# La ESP destino puede ser más grande que la original (4 GiB vs 1 GiB). Un dd
# dejaría los 3 GiB extras sin filesystem. Recreamos FAT32 al tamaño completo
# de la partición usando el MISMO volume ID (blkid lo muestra como UUID) y
# copiamos el contenido: el bootloader y fstab no notan la diferencia.
ESP_VOLID="${SRC_ESP_UUID//-/}"
mkfs.fat -F32 -i "$ESP_VOLID" -n ESP "$P2" >/dev/null
SRC_ESP_MNT=$(mktemp -d)
DST_ESP_MNT=$(mktemp -d)
mount -o ro "$SOURCE_ESP" "$SRC_ESP_MNT"
mount "$P2" "$DST_ESP_MNT"
cp -a "$SRC_ESP_MNT"/. "$DST_ESP_MNT"/
sync
umount "$DST_ESP_MNT" "$SRC_ESP_MNT"
rmdir "$DST_ESP_MNT" "$SRC_ESP_MNT" 2>/dev/null || true

log "Copiando root ($SOURCE_ROOT -> $P3)..."
log "Esto copia $((SOURCE_SIZE / 1024 / 1024 / 1024)) GiB; puede tardar."
dd if="$SOURCE_ROOT" of="$P3" bs=64M conv=sparse,fsync status=progress

DST_ESP_UUID=$(blkid -s UUID -o value "$P2" || true)
DST_ROOT_UUID=$(blkid -s UUID -o value "$P3" || true)
[[ "$DST_ESP_UUID" == "$SRC_ESP_UUID" ]] || die "UUID del ESP no coincide ($DST_ESP_UUID != $SRC_ESP_UUID)"
[[ "$DST_ROOT_UUID" == "$SRC_ROOT_UUID" ]] || die "UUID del root no coincide ($DST_ROOT_UUID != $SRC_ROOT_UUID)"
log "UUIDs preservados."

log "Expandiendo Btrfs..."
mkdir -p /mnt
ux_run mount "montar Btrfs migrado para resize" mount -o subvol=@ "$P3" /mnt \
  || die "No se pudo montar $P3 (ver /var/log/ronin/ux-trace.jsonl)"
btrfs filesystem resize max /mnt
sync
df -h /mnt | sed 's/^/    /'
umount /mnt

log "Verificando ESP..."
fsck.fat -n "$P2" || warn "fsck.fat reportó advertencias"

if (( DO_CHECK == 1 )); then
  log "btrfs check --readonly (puede tardar)..."
  btrfs check --readonly "$P3" || warn "btrfs check reportó advertencias"
fi

REPORT=/var/log/ronin-migration.json
mkdir -p /var/log
jq -n \
  --arg date "$(timestamp)" \
  --arg source_disk "$SOURCE_DISK" \
  --arg source_root "$SOURCE_ROOT" \
  --arg source_esp "$SOURCE_ESP" \
  --arg target "$TARGET" \
  --arg target_model "$TARGET_MODEL" \
  --arg root_uuid "$SRC_ROOT_UUID" \
  --arg esp_uuid "$SRC_ESP_UUID" \
  --argjson target_bytes "$TARGET_SIZE" \
  '{schema:1,date:$date,source_disk:$source_disk,source_root:$source_root,source_esp:$source_esp,
    target:$target,target_model:$target_model,root_uuid:$root_uuid,esp_uuid:$esp_uuid,
    target_bytes:$target_bytes,status:"ok"}' > "$REPORT"
chmod 644 "$REPORT"

ux_log pass migrate "migracion completada" "target=$TARGET root_uuid=$SRC_ROOT_UUID" 0
log "MIGRACIÓN OK"
log "Reporte: $REPORT"
log "Siguiente: apagar, desconectar el origen y arrancar solo desde $TARGET."
log "Luego: bash $SCRIPT_DIR/90-verify.sh"
