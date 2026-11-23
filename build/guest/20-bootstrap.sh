#!/usr/bin/env bash
# =============================================================================
# F1.3 - pacstrap CachyOS base + chroot configure
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_live
load_config
make_report_dir

LOG="$REPORT_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

mountpoint -q /mnt || die "/mnt no está montado; ejecutar 10-partition.sh"
[[ "$(findmnt -n -o FSTYPE /mnt)" == "btrfs" ]] || die "/mnt no es Btrfs"

log "Actualizando índices de pacman del live..."
pacman -Syy --noconfirm

log "Instalando base CachyOS en /mnt..."
PACKAGES=(
  base base-devel
  linux-cachyos linux-cachyos-headers linux-firmware
  btrfs-progs dosfstools exfatprogs efibootmgr
  networkmanager openssh sudo zram-generator
  amd-ucode intel-ucode
  cachyos-keyring cachyos-mirrorlist
  pciutils usbutils jq git nano vim tmux htop btop
  ripgrep fd fzf zstd bash-completion man-db man-pages
  pacman-contrib less which inetutils
)

pacstrap -K /mnt "${PACKAGES[@]}"

log "Generando fstab preliminar..."
genfstab -U /mnt > /mnt/etc/fstab

log "Copiando scripts de build al sistema instalado..."
mkdir -p /mnt/root/build-scripts
cp -a "$REPO_DIR"/. /mnt/root/build-scripts/
chmod +x /mnt/root/build-scripts/guest/*.sh 2>/dev/null || true

log "Configurando el sistema (arch-chroot)..."
arch-chroot /mnt /root/build-scripts/guest/30-configure.sh

log "Desmontando..."
sync
umount -R /mnt

log "BOOTSTRAP OK"
log "Siguiente: reiniciar (sin ISO) y ejecutar .\\build.ps1 wait-ssh"

if [[ "${REBOOT_AFTER_BOOTSTRAP:-no}" == "yes" ]]; then
  log "Reiniciando..."
  reboot
fi
