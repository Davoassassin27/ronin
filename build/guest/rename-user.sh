#!/usr/bin/env bash
# =============================================================================
# Ronin - renombra el usuario principal y fija una password conocida.
# Uso (en el sistema instalado, o en chroot desde el live):
#   bash rename-user.sh <usuario_viejo> <usuario_nuevo> <password>
# Idempotente: si el usuario viejo ya no existe y el nuevo sí, no hace nada.
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
OLD="${1:?Falta usuario viejo}"
NEW="${2:?Falta usuario nuevo}"
PASS="${3:?Falta password}"

[[ "$OLD" =~ ^[a-z_][a-z0-9_-]*$ && "$NEW" =~ ^[a-z_][a-z0-9_-]*$ ]] \
  || die "Nombres de usuario inválidos"

if ! id "$OLD" >/dev/null 2>&1; then
  if id "$NEW" >/dev/null 2>&1; then
    log "El usuario ya es $NEW; solo se actualiza la password"
  else
    die "No existe $OLD ni $NEW"
  fi
else
  log "Renombrando $OLD -> $NEW"
  if getent group "$OLD" >/dev/null 2>&1 && ! getent group "$NEW" >/dev/null 2>&1; then
    groupmod -n "$NEW" "$OLD"
  fi
  usermod -l "$NEW" -d "/home/$NEW" -m -g "$NEW" "$OLD"
fi

printf '%s:%s\n' "$NEW" "$PASS" | chpasswd
log "Password actualizada para $NEW"

# --- sudoers ----------------------------------------------------------------
shopt -s nullglob
for f in /etc/sudoers.d/10-$OLD /etc/sudoers.d/20-${OLD}-verify; do
  [[ -f "$f" ]] || continue
  newf="${f//$OLD/$NEW}"
  sed -i "s/\b$OLD\b/$NEW/g" "$f"
  mv -f "$f" "$newf"
  chmod 440 "$newf"
  log "sudoers: $newf"
done

# --- SSH --------------------------------------------------------------------
for f in /etc/ssh/sshd_config.d/*.conf; do
  sed -i "s/\b$OLD\b/$NEW/g" "$f"
done
sshd -t || die "sshd_config inválido tras el renombrado"

# --- SDDM autologin ---------------------------------------------------------
for f in /etc/sddm.conf.d/*.conf; do
  sed -i "s/^User=$OLD$/User=$NEW/" "$f"
done

# --- Ollama y otras rutas absolutas del home --------------------------------
for f in /etc/systemd/system/ollama.service.d/*.conf; do
  sed -i "s#/home/$OLD#/home/$NEW#g" "$f"
done

# --- Metadatos del build ----------------------------------------------------
[[ -f /etc/ronin-release ]] && sed -i "s/\b$OLD\b/$NEW/g" /etc/ronin-release
[[ -f /etc/hw-adapt.conf ]] && sed -i "s/\b$OLD\b/$NEW/g" /etc/hw-adapt.conf
[[ -f /root/build-scripts/build.env ]] && sed -i "s/^TARGET_USER=.*/TARGET_USER=$NEW/" /root/build-scripts/build.env

# --- Symlink /usr/share/omarchy (apunta al home del usuario) ----------------
if [[ -L /usr/share/omarchy ]]; then
  target=$(readlink /usr/share/omarchy)
  ln -sfn "${target//\/home\/$OLD/\/home\/$NEW}" /usr/share/omarchy
  log "symlink /usr/share/omarchy -> $(readlink /usr/share/omarchy)"
fi

# --- Symlinks internos que apuntaban al home viejo --------------------------
# Ojo: /home suele ser un subvolumen aparte, así que `find / -xdev` se lo saltea.
# Se recorren las bases relevantes por separado y se compara el target real.
for base in /home /etc /usr /var /opt /root; do
  [[ -d "$base" ]] || continue
  while IFS= read -r link; do
    target=$(readlink "$link")
    case "$target" in
      "/home/$OLD"/*)
        ln -sfn "/home/$NEW/${target#/home/$OLD/}" "$link"
        ;;
    esac
  done < <(find "$base" -type l 2>/dev/null)
done

# --- Referencias de texto al path viejo en configs/estado -------------------
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  sed -i "s#/home/$OLD\b#/home/$NEW#g" "$f" 2>/dev/null || true
done < <(grep -RIl "/home/$OLD\b" "/home/$NEW/.config" "/home/$NEW/.local/state" /etc 2>/dev/null)

# --- Home y permisos --------------------------------------------------------
chown -R "$NEW:$NEW" "/home/$NEW"
if [[ -d "/home/$NEW/.ssh" ]]; then
  chmod 700 "/home/$NEW/.ssh"
  [[ -f "/home/$NEW/.ssh/authorized_keys" ]] && chmod 600 "/home/$NEW/.ssh/authorized_keys"
fi

visudo -cf /etc/sudoers >/dev/null || die "sudoers inválido"

ux_log pass identity "usuario renombrado" "old=$OLD new=$NEW" 0
log "OK: usuario=$NEW home=/home/$NEW"
log "Verificar: id $NEW; grep -r $NEW /etc/sddm.conf.d /etc/ssh/sshd_config.d"
