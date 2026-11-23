#!/usr/bin/env bash
# =============================================================================
# F1.4 - Configuración del sistema instalado (chroot)
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
load_config
make_report_dir

LOG="$REPORT_DIR/configure-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

ROOT_UUID=$(read_state ROOT_UUID "")
ESP_UUID=$(read_state ESP_UUID "")
[[ -n "$ROOT_UUID" && -n "$ESP_UUID" ]] || die "Faltan UUIDs en $STATE_FILE"

log "Configurando Ronin en chroot"
log "Hostname: $TARGET_HOSTNAME / usuario: $TARGET_USER"

# --- Repositorios CachyOS (x86-64-v3) ---------------------------------------
configure_cachyos_repos || warn "No se pudieron configurar los repos CachyOS"
if pacman -Syy --noconfirm >/dev/null 2>&1; then
  log "Índices de pacman actualizados"
else
  warn "No se pudieron sincronizar los índices de pacman"
fi

# --- Reloj, locale, consola -------------------------------------------------
ln -sf "/usr/share/zoneinfo/$TARGET_TIMEZONE" /etc/localtime
hwclock --systohc 2>/dev/null || warn "hwclock no disponible en chroot (se ajustará al boot)"

# shellcheck disable=SC2016
sed -i 's/^#\?en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
if grep -q "^#\?${TARGET_LOCALE}" /etc/locale.gen; then
  sed -i "s/^#\?${TARGET_LOCALE}/${TARGET_LOCALE}/" /etc/locale.gen
else
  warn "Locale $TARGET_LOCALE no está en /etc/locale.gen; se usa en_US.UTF-8"
  TARGET_LOCALE="en_US.UTF-8"
fi
locale-gen

printf 'LANG=%s\n' "$TARGET_LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "$TARGET_KEYMAP" > /etc/vconsole.conf

printf '%s\n' "$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${TARGET_HOSTNAME}.localdomain ${TARGET_HOSTNAME}
EOF

# --- Usuario y sudo ---------------------------------------------------------
groupadd -f docker
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  useradd -m -G "$TARGET_GROUPS" -s "$TARGET_SHELL" "$TARGET_USER"
  log "Usuario creado: $TARGET_USER"
else
  log "Usuario ya existe: $TARGET_USER"
fi
usermod -aG docker "$TARGET_USER"

SUDOERS="/etc/sudoers.d/10-${TARGET_USER}"
printf '%s ALL=(ALL:ALL) ALL\n' "$TARGET_USER" > "$SUDOERS"
chmod 440 "$SUDOERS"
visudo -cf /etc/sudoers >/dev/null || die "sudoers inválido"

# --- Passwords ---------------------------------------------------------------
CRED_FILE=/root/build-credentials.txt
gen_password() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-20; }

if [[ -n "${TARGET_PASSWORD:-}" ]]; then
  printf '%s:%s\n' "$TARGET_USER" "$TARGET_PASSWORD" | chpasswd
else
  TARGET_PASSWORD=$(gen_password)
  printf '%s:%s\n' "$TARGET_USER" "$TARGET_PASSWORD" | chpasswd
  {
    echo "Ronin - credenciales generadas $(timestamp)"
    echo "usuario: $TARGET_USER"
    echo "password: $TARGET_PASSWORD"
  } > "$CRED_FILE"
  log "Password de $TARGET_USER generado en $CRED_FILE"
fi

if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd
else
  ROOT_PASSWORD=$(gen_password)
  printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd
  if [[ -f "$CRED_FILE" ]]; then
    echo "root password: $ROOT_PASSWORD" >> "$CRED_FILE"
  else
    {
      echo "Ronin - credenciales generadas $(timestamp)"
      echo "root password: $ROOT_PASSWORD"
    } > "$CRED_FILE"
  fi
fi
chmod 600 "$CRED_FILE" 2>/dev/null || true

# --- SSH ---------------------------------------------------------------------
install -d -m 700 /root/.ssh
# El .ssh del usuario debe ser suyo: si queda en root:root, sshd con
# StrictModes rechaza la clave y el usuario no puede entrar tras finalize.
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.ssh"
if [[ -f "$REPO_DIR/authorized_keys" ]]; then
  install -m 600 "$REPO_DIR/authorized_keys" /root/.ssh/authorized_keys
  install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" "$REPO_DIR/authorized_keys" "/home/$TARGET_USER/.ssh/authorized_keys"
  log "authorized_keys instalada para root y $TARGET_USER"
else
  warn "No hay $REPO_DIR/authorized_keys; SSH solo funcionará con password"
fi

install -d -m 755 /etc/ssh/sshd_config.d
ssh-keygen -A >/dev/null 2>&1 || warn "No se pudieron generar host keys de SSH"
cat > /etc/ssh/sshd_config.d/10-ronin.conf <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
AllowUsers $TARGET_USER root
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
sshd -t || die "Configuración de sshd inválida"
systemctl enable sshd >/dev/null

# --- fstab por UUID ----------------------------------------------------------
cat > /etc/fstab <<EOF
# Ronin - generado por 30-configure.sh. No editar a mano sin actualizar el build.
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$ROOT_UUID  /              btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@  0 0
UUID=$ROOT_UUID  /home          btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@home  0 0
UUID=$ROOT_UUID  /var/cache     btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@var_cache  0 0
UUID=$ROOT_UUID  /var/log       btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@var_log  0 0
UUID=$ROOT_UUID  /var/lib/docker btrfs rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@docker  0 0
UUID=$ROOT_UUID  /.snapshots    btrfs  rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@snapshots  0 0
UUID=$ESP_UUID   /boot          vfat   rw,umask=0077  0 2
EOF

# --- zram --------------------------------------------------------------------
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# --- sysctl ------------------------------------------------------------------
cat > /etc/sysctl.d/99-ronin.conf <<'EOF'
# Ronin - tuning para zram y portabilidad
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
EOF

# --- initramfs universal -----------------------------------------------------
if [[ -f "$REPO_DIR/config/etc/mkinitcpio.conf" ]]; then
  install -m 644 "$REPO_DIR/config/etc/mkinitcpio.conf" /etc/mkinitcpio.conf
else
  warn "No se encontró mkinitcpio.conf en config; usando el del sistema"
fi

log "Generando initramfs..."
mkinitcpio -P

# --- systemd-boot ------------------------------------------------------------
if [[ -f /boot/vmlinuz-linux-cachyos ]]; then
  log "Instalando systemd-boot..."
  bootctl --esp-path=/boot --no-variables install 2>/dev/null || bootctl --esp-path=/boot install
  install -d -m 755 /boot/EFI/BOOT
  if [[ -f /boot/EFI/systemd/systemd-bootx64.efi ]]; then
    install -m 644 /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
  elif [[ -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi ]]; then
    install -m 644 /usr/lib/systemd/boot/efi/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
  else
    die "No se encontró systemd-bootx64.efi"
  fi

  cat > /boot/loader/loader.conf <<'EOF'
default ronin.conf
timeout 3
console-mode max
editor no
EOF

  mkdir -p /boot/loader/entries
  INITRDS=()
  [[ -f /boot/intel-ucode.img ]] && INITRDS+=("/intel-ucode.img")
  [[ -f /boot/amd-ucode.img ]] && INITRDS+=("/amd-ucode.img")
  INITRDS+=("/initramfs-linux-cachyos.img")

  {
    echo "title   Ronin (CachyOS + Omarchy)"
    echo "linux   /vmlinuz-linux-cachyos"
    for initrd in "${INITRDS[@]}"; do echo "initrd  $initrd"; done
    echo "options root=UUID=$ROOT_UUID rw rootflags=subvol=@ usbcore.autosuspend=-1"
  } > /boot/loader/entries/ronin.conf

  log "Boot entry:"
  sed 's/^/    /' /boot/loader/entries/ronin.conf
else
  warn "No se encontró /boot/vmlinuz-linux-cachyos; no se instaló systemd-boot"
fi

# --- Servicios ---------------------------------------------------------------
systemctl enable NetworkManager >/dev/null
systemctl enable systemd-timesyncd >/dev/null
systemctl enable fstrim.timer >/dev/null
systemctl set-default graphical.target >/dev/null

# --- Metadatos ---------------------------------------------------------------
mkdir -p /var/log/ronin
{
  echo "build_date=$(timestamp)"
  echo "hostname=$TARGET_HOSTNAME"
  echo "user=$TARGET_USER"
  echo "root_uuid=$ROOT_UUID"
  echo "esp_uuid=$ESP_UUID"
  echo "kernel=linux-cachyos"
} > /etc/ronin-release
chmod 644 /etc/ronin-release

log "Verificación rápida:"
findmnt --verify 2>&1 | sed 's/^/    /' || warn "findmnt --verify reportó advertencias"
bootctl --esp-path=/boot status 2>&1 | sed 's/^/    /' || true

log "CONFIGURE OK"
log "Siguiente: reiniciar sin ISO y ejecutar .\\build.ps1 wait-ssh"
