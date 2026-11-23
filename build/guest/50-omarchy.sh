#!/usr/bin/env bash
# =============================================================================
# F2 - Overlay Omarchy sobre CachyOS + SDDM/Hyprland
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/omarchy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

if [[ "$INSTALL_OMARCHY" != "yes" ]]; then
  log "INSTALL_OMARCHY != yes; se omite F2."
  exit 0
fi
if [[ "$OMARCHY_MODE" == "off" ]]; then
  log "OMARCHY_MODE=off; se omite F2."
  exit 0
fi
if [[ "$OMARCHY_MODE" != "overlay" ]]; then
  warn "OMARCHY_MODE=$OMARCHY_MODE no está implementado; usar overlay."
  exit 1
fi

USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "No se encontró home de $TARGET_USER"
OMARCHY_PATH="$USER_HOME/.local/share/omarchy"
OMARCHY_REQUIRED="${OMARCHY_REQUIRED:-yes}"

# --- 1. Paquetes base del escritorio ----------------------------------------
log "Instalando escritorio Hyprland/Omarchy..."
DESKTOP_PKGS=(
  hyprland hypridle hyprlock hyprpicker hyprsunset hyprland-guiutils
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  polkit-gnome gnome-keyring libsecret
  sddm uwsm
  waybar mako swaybg grim slurp wl-clipboard
  imagemagick inotify-tools qt6-imageformats
  foot alacritty
  brightnessctl playerctl pamixer wiremix
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
  nautilus gnome-disk-utility
  qt5-wayland qt6-wayland
  xdg-terminal-exec
  gum jq
)
install_pkgs "${DESKTOP_PKGS[@]}" || warn "Algunos paquetes de escritorio no se instalaron"

# --- 2. Repo Omarchy (solo paquetes omarchy-*) -------------------------------
log "Configurando repo [omarchy]..."
cat > /etc/pacman.d/omarchy.conf <<'EOF'
[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/$arch
EOF

if ! grep -q '^Include = /etc/pacman.d/omarchy.conf' /etc/pacman.conf; then
  printf '\n# Ronin - repo Omarchy (paquetes omarchy-*)\nInclude = /etc/pacman.d/omarchy.conf\n' >> /etc/pacman.conf
fi

if pacman -Sy --noconfirm >/dev/null 2>&1; then
  install_pkgs omarchy-keyring || warn "omarchy-keyring no disponible"
  # Paquete principal: pone los ~2300 archivos y binarios omarchy-* en /usr y
  # /usr/share/omarchy. Se asumen los paquetes de Limine (usamos systemd-boot)
  # y la fuente nerd "basic" (ya instalamos la completa) para evitar conflictos.
  pacman -S --needed --noconfirm \
    --assume-installed limine \
    --assume-installed limine-mkinitcpio-hook \
    --assume-installed limine-snapper-sync \
    --assume-installed snapper \
    --assume-installed ttf-jetbrains-mono-nerd-basic \
    omarchy >/dev/null 2>&1 \
    && log "Instalado: omarchy" || warn "omarchy no se pudo instalar"
  # Sus drop-ins de mkinitcpio reemplazan los HOOKS universales y piden el hook
  # btrfs-overlayfs (inexistente acá): desactivarlos y regenerar el initramfs.
  for f in 00-omarchy-hooks.conf omarchy_hooks.conf omarchy_vconsole.conf; do
    [[ -f "/etc/mkinitcpio.conf.d/$f" ]] && mv "/etc/mkinitcpio.conf.d/$f" "/etc/mkinitcpio.conf.d/$f.disabled"
  done
  mkinitcpio -P >/dev/null 2>&1 || warn "mkinitcpio falló tras instalar omarchy"
  for pkg in omarchy-nvim walker quickshell omarchy-hyprland-titlebars; do
    pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1 && log "Instalado: $pkg" || warn "No disponible: $pkg"
  done
else
  warn "No se pudo sincronizar el repo Omarchy; se continúa con el overlay de configuración."
fi

# --- 3. Clonar Omarchy pinneado ---------------------------------------------
log "Clonando Omarchy ($OMARCHY_REF)..."
install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$(dirname "$OMARCHY_PATH")"

if [[ -d "$OMARCHY_PATH/.git" ]]; then
  sudo -u "$TARGET_USER" git -C "$OMARCHY_PATH" fetch --depth 1 origin "$OMARCHY_REF"
  sudo -u "$TARGET_USER" git -C "$OMARCHY_PATH" reset --hard FETCH_HEAD
else
  if ! sudo -u "$TARGET_USER" git clone --depth 1 --branch "$OMARCHY_REF" "$OMARCHY_REPO" "$OMARCHY_PATH"; then
    if [[ "$OMARCHY_REQUIRED" == "yes" ]]; then
      die "No se pudo clonar Omarchy. Revisar red/OMARCHY_REF o usar OMARCHY_REQUIRED=no."
    fi
    warn "Sin clone de Omarchy; se continúa en modo degradado."
  fi
fi

OMARCHY_COMMIT=""
if [[ -d "$OMARCHY_PATH/.git" ]]; then
  OMARCHY_COMMIT=$(sudo -u "$TARGET_USER" git -C "$OMARCHY_PATH" rev-parse HEAD)
  write_state OMARCHY_COMMIT "$OMARCHY_COMMIT"
  log "Omarchy commit: $OMARCHY_COMMIT"
fi

# --- 4. Configs ---------------------------------------------------------------
if [[ -d "$OMARCHY_PATH/config" ]]; then
  log "Copiando configs de Omarchy a ~/.config..."
  install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$USER_HOME/.config"
  cp -a "$OMARCHY_PATH/config/." "$USER_HOME/.config/"
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config"
else
  warn "No existe $OMARCHY_PATH/config; se usará Hyprland sin configs de Omarchy."
fi

if [[ -f "$OMARCHY_PATH/default/bashrc" ]]; then
  cp "$OMARCHY_PATH/default/bashrc" "$USER_HOME/.bashrc"
  chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.bashrc"
fi

# Omarchy (overlay) espera /usr/share/omarchy. Sus scripts —env-bootstrap,
# default/hypr/bootstrap.lua, .bashrc— usan esa ruta por defecto. Sin esto,
# Hyprland arranca con OMARCHY_PATH vacío y falla con "/bootstrap.lua".
# Si el paquete `omarchy` se instaló, /usr/share/omarchy ya es real. El symlink
# queda solo como fallback para builds sin el paquete (modo overlay puro).
if [[ ! -e /usr/share/omarchy ]]; then
  install -d -m 755 /usr/share
  ln -sfn "$OMARCHY_PATH" /usr/share/omarchy
fi

# OMARCHY_PATH también para la sesión SDDM/Hyprland, que no lee bashrc.
grep -q '^OMARCHY_PATH=' /etc/environment 2>/dev/null \
  || printf 'OMARCHY_PATH=%s\n' "$OMARCHY_PATH" >> /etc/environment

# profile.d: sourcear el env-bootstrap de Omarchy (define OMARCHY_PATH + PATH).
cat > /etc/profile.d/omarchy.sh <<'EOF'
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap
export PATH="$OMARCHY_PATH/bin:$PATH"
EOF
chmod 644 /etc/profile.d/omarchy.sh

# Toggles iniciales (si existen en el repo)
if [[ -d "$OMARCHY_PATH/default/hypr/toggles" ]]; then
  install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$USER_HOME/.local/state/omarchy/toggles/hypr"
  cp -a "$OMARCHY_PATH/default/hypr/toggles/." "$USER_HOME/.local/state/omarchy/toggles/hypr/"
  chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.local/state/omarchy"
fi

# Tema inicial (best effort; requiere DBus/entorno)
if [[ -x "$OMARCHY_PATH/bin/omarchy-theme-set" ]]; then
  sudo -u "$TARGET_USER" env OMARCHY_PATH="$OMARCHY_PATH" PATH="$OMARCHY_PATH/bin:$PATH" \
    "$OMARCHY_PATH/bin/omarchy-theme-set" "Tokyo Night" >/dev/null 2>&1 \
    && log "Tema Tokyo Night aplicado" || warn "No se pudo aplicar el tema inicial (se hará al login)"
fi

# Omarchy 4.5 usa configuración Lua (hl.env / hl.monitor).
HYPR_LUA="$USER_HOME/.config/hypr/hyprland.lua"
install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$(dirname "$HYPR_LUA")"
if [[ ! -f "$HYPR_LUA" ]]; then
  cat > "$HYPR_LUA" <<'EOF'
-- Ronin - configuración mínima de Hyprland (Lua).
require("hypr.hardware-auto")
EOF
  chown "$TARGET_USER:$TARGET_USER" "$HYPR_LUA"
fi
if ! grep -q 'require("hypr.hardware-auto")' "$HYPR_LUA"; then
  printf '\n-- Ronin hardware\nrequire("hypr.hardware-auto")\n' >> "$HYPR_LUA"
fi
chown "$TARGET_USER:$TARGET_USER" "$HYPR_LUA"

# Limpiar el .conf legacy que creaban versiones anteriores del build.
if [[ -f "$USER_HOME/.config/hypr/hyprland.conf" ]] && grep -q 'Ronin - configuración mínima' "$USER_HOME/.config/hypr/hyprland.conf"; then
  rm -f "$USER_HOME/.config/hypr/hyprland.conf"
fi

# --- 5. SDDM ----------------------------------------------------------------
log "Configurando SDDM..."
install -d -m 755 /usr/local/share/wayland-sessions
install -d -m 755 /etc/sddm.conf.d
install -d -m 755 /usr/share/sddm

# El paquete oficial pone los binarios en /usr/bin; nuestro overlay los tiene
# en $OMARCHY_PATH/bin. El wrapper los expone en PATH antes de uwsm/Hyprland,
# o el autostart no encuentra omarchy-launch-shell / provision-first-run.
cat > /usr/local/bin/ronin-session <<'EOF'
#!/bin/bash
export OMARCHY_PATH=/usr/share/omarchy
export PATH="$OMARCHY_PATH/bin:$PATH"
exec uwsm start -g -1 -e -D Hyprland hyprland.desktop
EOF
chmod 755 /usr/local/bin/ronin-session

cat > /usr/local/share/wayland-sessions/omarchy.desktop <<'EOF'
[Desktop Entry]
Name=Omarchy (Hyprland uwsm)
Comment=Omarchy Hyprland session managed by ronin-session
Exec=/usr/local/bin/ronin-session
TryExec=/usr/local/bin/ronin-session
Type=Application
EOF

if [[ -f "$OMARCHY_PATH/default/sddm/hyprland.conf" ]]; then
  cp "$OMARCHY_PATH/default/sddm/hyprland.conf" /usr/share/sddm/hyprland.conf
else
  cat > /usr/share/sddm/hyprland.conf <<'EOF'
monitor=,preferred,auto,1
exec-once = sddm-greeter-qt6 --socket /tmp/sddm-greeter.sock
EOF
fi

COMPOSITOR_CMD="start-hyprland -- --config /usr/share/sddm/hyprland.conf"
if ! command -v start-hyprland >/dev/null 2>&1; then
  COMPOSITOR_CMD="Hyprland --config /usr/share/sddm/hyprland.conf"
fi
cat > /etc/sddm.conf.d/10-wayland.conf <<EOF
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=$COMPOSITOR_CMD
EOF

THEME_BLOCK=""
if [[ -d /usr/share/sddm/themes/omarchy ]]; then
  THEME_BLOCK=$'[Theme]\nCurrent=omarchy\n'
fi
if [[ "$OMARCHY_AUTOLOGIN" == "yes" ]]; then
  cat > /etc/sddm.conf.d/20-autologin.conf <<EOF
[Autologin]
User=$TARGET_USER
Session=omarchy

$THEME_BLOCK
EOF
else
  cat > /etc/sddm.conf.d/20-autologin.conf <<'EOF'
[Autologin]
User=
Session=
EOF
fi

systemctl enable sddm.service >/dev/null
systemctl set-default graphical.target >/dev/null

# --- 5.5 Tema Ronin (tech, base Kanagawa) -----------------------------------
RONIN_THEME="$USER_HOME/.config/omarchy/themes/ronin"
if [[ -d /usr/share/omarchy/themes/kanagawa ]]; then
  install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$RONIN_THEME"
  cp -a /usr/share/omarchy/themes/kanagawa/. "$RONIN_THEME/"
  rm -f "$RONIN_THEME/backgrounds/1-kanagawa.jpg"

  # Arte: Utagawa Yoshifusa, "Miyamoto Musashi y Sasaki Kojiro en Ganryujima"
  # (c. 1843-1847), dominio publico. Fuente: Wikimedia Commons.
  WALL_SRC=""
  if [[ -f "$REPO_DIR/config/home/ronin-wallpaper-ganryujima.jpg" ]]; then
    WALL_SRC="$REPO_DIR/config/home/ronin-wallpaper-ganryujima.jpg"
  elif [[ -f "$REPO_DIR/config/home/ronin-wallpaper.svg" ]]; then
    WALL_SRC="$REPO_DIR/config/home/ronin-wallpaper.svg"
  fi

  if [[ -n "$WALL_SRC" ]] && command -v magick >/dev/null 2>&1; then
    magick "$WALL_SRC" -auto-orient -resize 2560x1440^ -gravity center \
      -extent 2560x1440 -strip "$RONIN_THEME/backgrounds/1-ronin.png"
    magick "$RONIN_THEME/backgrounds/1-ronin.png" -resize 800x450 "$RONIN_THEME/preview.png"
    sed -i 's/^accent = .*/accent = "#e6c384"/' "$RONIN_THEME/colors.toml"
    chown -R "$TARGET_USER:$TARGET_USER" "$RONIN_THEME"
    sudo -u "$TARGET_USER" -H env OMARCHY_PATH=/usr/share/omarchy \
      omarchy-theme-set ronin >/dev/null 2>&1 \
      && log "Tema Ronin (tech) aplicado con arte de Musashi" \
      || warn "Tema Ronin creado; se aplicará al primer login"
  else
    warn "No se pudo generar el wallpaper Ronin (falta magick o la imagen)"
  fi
fi

# --- 6. Validación -----------------------------------------------------------
for cmd in hyprctl sddm; do
  command -v "$cmd" >/dev/null 2>&1 || die "Falta $cmd; revisar la instalación de paquetes"
done

systemctl is-enabled sddm.service >/dev/null 2>&1 || die "sddm no quedó habilitado"
grep -q 'require("hypr.hardware-auto")' "$HYPR_LUA" || die "hyprland.lua no referencia hardware-auto.lua"

log "Escritorio: $(hyprctl version 2>/dev/null | head -n1 || echo 'Hyprland instalado (sin sesión activa)')"
log "SDDM: $(systemctl is-enabled sddm.service)"
log "Omarchy: ${OMARCHY_COMMIT:-sin commit (modo degradado)}"
log "OMARCHY OK (overlay)"
log "Nota: la validación visual de Hyprland requiere sesión gráfica (QEMU/VNC o hardware real)."
