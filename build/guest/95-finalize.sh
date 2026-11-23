#!/usr/bin/env bash
# =============================================================================
# F6 - Finalización: verificación final, root SSH off, manifiesto
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/finalize-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Finalizando Ronin"

# Defensivo: .ssh del usuario debe pertenecerle (StrictModes). 30-configure.sh
# ya lo crea bien, pero un build anterior pudo dejarlo en root:root.
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -d "$USER_HOME/.ssh" ]]; then
  chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$USER_HOME/.ssh"
  chmod 700 "$USER_HOME/.ssh"
  [[ -f "$USER_HOME/.ssh/authorized_keys" ]] && chmod 600 "$USER_HOME/.ssh/authorized_keys"
fi

# --- SSH: solo el usuario, sin root -----------------------------------------
SSH_DROPIN=/etc/ssh/sshd_config.d/10-ronin.conf
cat > "$SSH_DROPIN" <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $TARGET_USER
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sshd -t || die "Configuración SSH inválida"

# Verificación final con la config de SSH ya aplicada, pero antes de cortar
# la sesión root actual.
log "Ejecutando verificación final (root SSH todavía activo)..."
if ! EXPECT_ROOT_DISABLED=1 bash "$SCRIPT_DIR/90-verify.sh"; then
  warn "La verificación falló; se restaura root SSH (clave) para depurar."
  cat > "$SSH_DROPIN" <<EOF
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
AllowUsers $TARGET_USER root
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  sshd -t && systemctl restart sshd || true
  die "Finalize abortado: corregir 90-verify.sh y reejecutar."
fi

rm -f /root/.ssh/authorized_keys
systemctl restart sshd
log "Root SSH deshabilitado."

# Permitir que el usuario corra la verificación por sudo sin password.
BASH_BIN=$(command -v bash)
printf '%s ALL=(root) NOPASSWD: %s /root/build-scripts/guest/90-verify.sh\n' \
  "$TARGET_USER" "$BASH_BIN" > "/etc/sudoers.d/20-${TARGET_USER}-verify"
chmod 440 "/etc/sudoers.d/20-${TARGET_USER}-verify"
visudo -cf /etc/sudoers >/dev/null || die "sudoers inválido"

# --- Manifiesto --------------------------------------------------------------
install -d -m 755 /etc/ronin /var/log/ronin
pacman -Qqe > /var/log/ronin/packages.txt
pacman -Qqe | wc -l > /var/log/ronin/package-count.txt

OMARCHY_COMMIT=""
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -d "$USER_HOME/.local/share/omarchy/.git" ]]; then
  OMARCHY_COMMIT=$(sudo -u "$TARGET_USER" git -C "$USER_HOME/.local/share/omarchy" rev-parse HEAD 2>/dev/null || true)
fi

KERNEL=$(uname -r)
ROOT_UUID=$(findmnt -no UUID /)
ESP_UUID=$(findmnt -no UUID /boot)
PKG_COUNT=$(wc -l < /var/log/ronin/packages.txt)

jq -n \
  --arg date "$(timestamp)" \
  --arg hostname "$TARGET_HOSTNAME" \
  --arg kernel "$KERNEL" \
  --arg root_uuid "$ROOT_UUID" \
  --arg esp_uuid "$ESP_UUID" \
  --arg omarchy_commit "$OMARCHY_COMMIT" \
  --argjson packages "$PKG_COUNT" \
  '{date:$date, hostname:$hostname, kernel:$kernel, root_uuid:$root_uuid,
    esp_uuid:$esp_uuid, omarchy_commit:(if $omarchy_commit=="" then null else $omarchy_commit end),
    packages:$packages, schema:1}' > /etc/ronin/build-manifest.json
chmod 644 /etc/ronin/build-manifest.json

sha256sum /boot/vmlinuz-linux-cachyos /boot/initramfs-linux-cachyos.img \
  > /etc/ronin/boot.sha256 2>/dev/null || true

chmod 700 /root/build-scripts
chmod -R go-rwx /root/build-scripts 2>/dev/null || true

log "Root SSH deshabilitado. Usar: .\\build.ps1 ssh -User $TARGET_USER"
log "Manifiesto: /etc/ronin/build-manifest.json"
log "Paquetes: $PKG_COUNT"
log "Omarchy commit: ${OMARCHY_COMMIT:-no disponible}"
log "FINALIZE OK"
