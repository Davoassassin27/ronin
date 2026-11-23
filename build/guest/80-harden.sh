#!/usr/bin/env bash
# =============================================================================
# F6 - Hardening (sin bloquear el build)
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/harden-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Aplicando hardening"

# --- SSH (root sigue permitido con clave hasta 95-finalize) ------------------
cat > /etc/ssh/sshd_config.d/10-ronin.conf <<EOF
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
sshd -t || die "Configuración SSH inválida"
systemctl restart sshd
log "SSH endurecido (password off, root solo clave)"

# --- sysctl ------------------------------------------------------------------
cat > /etc/sysctl.d/99-ronin.conf <<'EOF'
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
sysctl --system >/dev/null

# --- journald ----------------------------------------------------------------
install -d -m 755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/10-ronin.conf <<'EOF'
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=100M
RuntimeMaxUse=200M
Compress=yes
EOF
systemctl restart systemd-journald

# --- Firewall ----------------------------------------------------------------
if install_pkgs ufw; then
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw limit ssh/tcp >/dev/null
  ufw --force enable >/dev/null
  systemctl enable ufw.service >/dev/null
  log "UFW activo: deny incoming, allow outgoing, limit ssh"
else
  warn "ufw no se pudo instalar; quedará como check fallido en la verificación"
fi

systemctl enable systemd-timesyncd >/dev/null

# --- Auditoría de build ------------------------------------------------------
chmod -R go-rwx /root/build-scripts 2>/dev/null || true

pacman -Qqe > /var/log/ronin/packages-harden.txt 2>/dev/null || true

log "SSH: $(sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|allowusers)' | tr '\n' ' ')"
log "UFW: $(ufw status 2>/dev/null | head -n1 || echo 'no disponible')"
log "HARDEN OK"
