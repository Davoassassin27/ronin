#!/usr/bin/env bash
# =============================================================================
# F3/F4 - Stack Dev/DevOps + AI local
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/dev-ai-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -d "$USER_HOME" ]] || die "No existe $USER_HOME"

# --- 1. Toolchain ------------------------------------------------------------
log "Instalando toolchain de desarrollo..."
DEV_PKGS=(
  git github-cli tmux neovim nano
  ripgrep fd fzf jq yq btop rclone
  uv python rustup go nodejs npm
  docker docker-compose docker-buildx kubectl helm lazydocker
  postgresql-libs sqlite duckdb
  openssh
)
install_pkgs "${DEV_PKGS[@]}" || warn "Algunos paquetes de desarrollo no se instalaron"

# --- 2. Vulkan / GPU ---------------------------------------------------------
log "Instalando stack Vulkan/VA-API..."
GPU_PKGS=(
  vulkan-icd-loader vulkan-tools mesa
  vulkan-radeon vulkan-intel
  libva libva-utils
  nvtop radeontop
)
install_pkgs "${GPU_PKGS[@]}" || warn "Algunos paquetes GPU no se instalaron"

if [[ "$INSTALL_NVIDIA" == "yes" ]]; then
  log "Instalando drivers NVIDIA open (portabilidad)..."
  install_pkgs nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
    || warn "NVIDIA no se pudo instalar; el sistema seguirá con Mesa/AMD/Intel."
elif [[ "$INSTALL_NVIDIA" == "auto" ]] && lspci 2>/dev/null | grep -qi nvidia; then
  install_pkgs nvidia-open-dkms nvidia-utils lib32-nvidia-utils || warn "NVIDIA falló"
fi

# lib32 requiere multilib; habilitarlo de forma idempotente.
if grep -q '^#\[multilib\]' /etc/pacman.conf; then
  log "Habilitando repositorio multilib..."
  sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
  pacman -Sy --noconfirm || warn "No se pudo refrescar multilib"
fi

install_pkgs lib32-vulkan-radeon lib32-vulkan-intel lib32-mesa \
  || warn "lib32 no disponible (multilib deshabilitado?)"

# Rust toolchain por defecto (descarga; best effort)
if command -v rustup >/dev/null 2>&1; then
  log "Configurando rustup stable..."
  # -H es clave: sin él sudo conserva HOME=/root y rustup escribe en /root/.rustup,
  # dejando el toolchain del usuario sin configurar (DEV-01 falla después).
  sudo -u "$TARGET_USER" -H rustup default stable >/dev/null 2>&1 \
    && log "rustup stable OK" || warn "rustup default stable falló (revisar red)"
fi

# --- 3. Directorios de usuario ----------------------------------------------
log "Creando directorios de trabajo..."
install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" \
  "$USER_HOME/workspace" \
  "$USER_HOME/ai-models" \
  "$USER_HOME/ai-models/ollama" \
  "$USER_HOME/ai-models/huggingface" \
  "$USER_HOME/ai-models/datasets"

if [[ -f "$REPO_DIR/config/home/workspace-README.md" ]]; then
  install -m 644 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$REPO_DIR/config/home/workspace-README.md" "$USER_HOME/workspace/README.md"
fi

# --- 4. Docker ---------------------------------------------------------------
log "Configurando Docker..."
install -d -m 755 /etc/docker
install -m 644 "$REPO_DIR/config/etc/docker/daemon.json" /etc/docker/daemon.json
usermod -aG docker "$TARGET_USER"
systemctl enable docker.service >/dev/null
restart_if_booted docker.service

# --- 5. Ollama ---------------------------------------------------------------
log "Instalando Ollama..."
if ! install_pkgs ollama; then
  warn "ollama no está en los repos; intentando ollama-rocm/ollama-cuda..."
  install_pkgs ollama-rocm || install_pkgs ollama-cuda || warn "Ollama no se pudo instalar"
fi

if getent group ollama >/dev/null 2>&1; then
  usermod -aG ollama "$TARGET_USER"
  # El servicio corre como 'ollama' y necesita atravesar el home del usuario.
  usermod -aG "$TARGET_USER" ollama
  chmod 0750 "$USER_HOME"
  chown -R ollama:ollama "$USER_HOME/ai-models/ollama"
  chmod 0750 "$USER_HOME/ai-models/ollama"
else
  warn "Grupo ollama no existe; revisar el paquete antes de usar el servicio"
fi

if systemctl cat ollama.service >/dev/null 2>&1; then
  install -d -m 755 /etc/systemd/system/ollama.service.d
  sed "s|@HOME@|$USER_HOME|g" \
    "$REPO_DIR/config/etc/systemd/system/ollama.service.d/override.conf" \
    > /etc/systemd/system/ollama.service.d/override.conf
  systemctl daemon-reload
  systemctl enable ollama.service >/dev/null
  restart_if_booted ollama.service
  log "Ollama habilitado (127.0.0.1:11434)"
else
  warn "No existe ollama.service; se omite la configuración del servicio"
fi

# --- 6. Verificación rápida -------------------------------------------------
pacman -Qqe > /var/log/ronin/packages-dev.txt 2>/dev/null || true

if is_booted; then
  log "Docker root: $(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo 'no disponible')"
  if curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    log "Ollama API OK"
  else
    warn "Ollama API todavía no responde (puede tardar en el primer arranque)"
  fi
  if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary >/dev/null 2>&1 && log "Vulkan OK" || warn "vulkaninfo falló"
  fi
fi

log "DEV/AI OK"
