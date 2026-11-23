#!/usr/bin/env bash
# =============================================================================
# F5 - Gaming bajo demanda
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

if [[ "$INSTALL_GAMING" != "yes" ]]; then
  log "INSTALL_GAMING != yes; se omite F5."
  exit 0
fi

LOG="$REPORT_DIR/gaming-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

log "Instalando stack de gaming..."
if ! install_pkgs cachyos-gaming-meta; then
  warn "cachyos-gaming-meta no disponible; instalando componentes por separado..."
  # Proton se gestiona desde Steam Play; no hay paquete proton-cachyos en los repos.
  install_pkgs steam gamemode lib32-gamemode mangohud lib32-mangohud \
    || warn "Algunos componentes de gaming no se instalaron"
fi

# GameMode es un servicio ligero; se deja como venga del paquete.
# Lo importante es no habilitar launchers pesados al boot.
if systemctl list-unit-files --state=enabled 2>/dev/null | grep -Ei 'steam|heroic|gog|bottles|lutris'; then
  warn "Hay launchers habilitados al boot; revisar y deshabilitar."
else
  log "OK: sin launchers de gaming habilitados al boot."
fi

USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if compgen -G "$USER_HOME/.config/autostart/*steam*" >/dev/null 2>&1; then
  warn "Hay autostart de Steam en ~/.config/autostart; quitarlo si no se desea."
fi

pacman -Qqe > /var/log/ronin/packages-gaming.txt 2>/dev/null || true

log "GAMING OK (bajo demanda)"
