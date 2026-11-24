#!/usr/bin/env bash
# =============================================================================
# F4.5 - Kensei CLI/TUI, modelo abliterado y memoria manual
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

LOG="$REPORT_DIR/kensei-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

[[ "${INSTALL_KENSEI:-yes}" == "yes" ]] || {
  log "INSTALL_KENSEI=no; se omite Kensei"
  exit 0
}

USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -d "$USER_HOME" ]] || die "No existe $USER_HOME"

KENSEI_SRC="${KENSEI_SRC:-$REPO_DIR/kensei}"

log "Instalando dependencias de shell/Python..."
KENSEI_PKGS=(
  zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions
  python-rich python-httpx python-pyyaml python-platformdirs curl git
)
install_pkgs "${KENSEI_PKGS[@]}" || warn "Faltan paquetes de Kensei; la TUI puede quedar incompleta"

if [[ ! -d "$KENSEI_SRC" ]]; then
  KENSEI_SRC=/opt/kensei-src
  log "Kensei no está vendorizado; clonando $KENSEI_REPO ($KENSEI_REF)..."
  rm -rf "$KENSEI_SRC"
  git clone --depth 1 --branch "$KENSEI_REF" "$KENSEI_REPO" "$KENSEI_SRC" \
    || die "No se pudo clonar Kensei. Clonalo en kensei/ antes de push o ajustá KENSEI_REPO/KENSEI_REF."
fi
[[ -f "$KENSEI_SRC/pyproject.toml" ]] || die "Fuente Kensei inválida: $KENSEI_SRC"

log "Instalando tte (animaciones) para $TARGET_USER..."
if ! command -v tte >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" -H uv tool install terminaltexteffects >/dev/null 2>&1 \
      || warn "tte no se instaló; se usa el banner ASCII de fallback"
  else
    warn "uv no está; no se puede instalar tte"
  fi
fi

log "Instalando Kensei en /usr/local..."
bash "$KENSEI_SRC/packaging/install.sh" --prefix /usr/local --source "$KENSEI_SRC"

DATA_DIR="$USER_HOME/.local/share/kensei"
install -d -m 755 -o "$TARGET_USER" -g "$TARGET_USER" "$DATA_DIR"

log "Construyendo RAG manual (Ronin + seguridad)..."
if [[ -f /usr/local/lib/kensei/scripts/normalize_corpus.py ]]; then
  sudo -u "$TARGET_USER" -H env \
    KENSEI_DATA_DIR="$DATA_DIR" \
    PYTHONPATH=/usr/local/lib/kensei/src \
    python3 /usr/local/lib/kensei/scripts/normalize_corpus.py \
      --only manual --out "$DATA_DIR" >/dev/null 2>&1 \
    || warn "No se pudo normalizar el manual para RAG"
  sudo -u "$TARGET_USER" -H env KENSEI_DATA_DIR="$DATA_DIR" \
    /usr/local/bin/kensei index \
      --chunks "$DATA_DIR/chunks.jsonl" --db "$DATA_DIR/kensei.db" >/dev/null 2>&1 \
    || warn "No se pudo construir el índice RAG manual"
else
  warn "No se encontró normalize_corpus.py; RAG queda vacío"
fi

log "Creando scope por defecto (authorized: false)..."
SCOPE_DIR="$USER_HOME/.config/kensei"
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$SCOPE_DIR"
if [[ ! -f "$SCOPE_DIR/scope.yaml" ]]; then
  sed 's/^authorized: true/authorized: false/' \
    /usr/local/lib/kensei/config/scope.example.yaml > "$SCOPE_DIR/scope.yaml" \
    || warn "No se pudo crear scope.yaml"
  chown "$TARGET_USER:$TARGET_USER" "$SCOPE_DIR/scope.yaml"
  chmod 600 "$SCOPE_DIR/scope.yaml"
fi

log "Configurando servicio de modelo abliterado (primer boot)..."
cat > /etc/systemd/system/kensei-model.service <<EOF
[Unit]
Description=Kensei abliterated model (download + Ollama create)
After=ollama.service network-online.target
Wants=network-online.target
ConditionPathExists=!$DATA_DIR/models/.kensei-model-ready

[Service]
Type=oneshot
User=$TARGET_USER
Group=$TARGET_USER
Environment=HOME=$USER_HOME
Environment=KENSEI_DATA_DIR=$DATA_DIR
Environment=KENSEI_MODEL=kensei
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/kensei-model
RemainAfterExit=yes
TimeoutStartSec=1800
StandardOutput=append:/var/log/ronin/kensei-model.log
StandardError=append:/var/log/ronin/kensei-model.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kensei-model.service >/dev/null
log "kensei-model.service habilitado (descarga en el primer boot)"

if [[ "${KENSEI_PRELOAD_MODEL:-no}" == "yes" ]]; then
  log "KENSEI_PRELOAD_MODEL=yes; descargando modelo ahora..."
  systemctl start kensei-model.service || warn "La descarga del modelo falló; se reintenta en el próximo boot"
fi

# Verificación mínima (sin bloquear si Ollama aún no cargó)
if [[ -x /usr/local/bin/kensei ]]; then
  zsh -n /usr/local/share/kensei/kensei.zsh && log "kensei.zsh sintaxis OK"
  zsh -n /usr/local/share/kensei/zsh/.zshrc && log "zshrc sintaxis OK"
else
  warn "No se instaló /usr/local/bin/kensei"
fi

log "KENSEI OK"
