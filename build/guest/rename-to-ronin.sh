#!/usr/bin/env bash
# =============================================================================
# Ronin - aplica la identidad "Ronin" a un sistema ya construido.
# Idempotente. Puede ejecutarse en el guest arrancado o desde chroot del live:
#   mount -o subvol=@    /dev/vda2 /mnt
#   mount -o subvol=@home /dev/vda2 /mnt/home
#   mount /dev/vda1 /mnt/boot
#   chroot /mnt bash /root/build-scripts/guest/rename-to-ronin.sh
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root

NAME="ronin"
OLD="work-os"
FLAG=/etc/ronin-identity-applied

log "Aplicando identidad Ronin"

# --- Hostname ----------------------------------------------------------------
printf '%s\n' "$NAME" > /etc/hostname
if [[ -f /etc/hosts ]]; then
  sed -i -E "s/127\.0\.1\.1[[:space:]].*/127.0.1.1 ${NAME}.localdomain ${NAME}/" /etc/hosts
fi

# --- Archivos de configuración con el nombre viejo ---------------------------
while IFS= read -r -d '' f; do
  new=${f//$OLD/$NAME}
  if [[ "$new" != "$f" ]]; then
    mv -f "$f" "$new"
    sed -i "s/Work OS/Ronin/g; s/work-os/ronin/g; s/WORK_OS/RONIN/g" "$new" 2>/dev/null || true
    log "Renombrado: $f -> $new"
  fi
done < <(find /etc -type f -name "*${OLD}*" -print0 2>/dev/null || true)

# --- systemd-boot ------------------------------------------------------------
if [[ -d /boot/loader/entries ]]; then
  old_entry=/boot/loader/entries/${OLD}.conf
  new_entry=/boot/loader/entries/${NAME}.conf
  if [[ -f "$old_entry" ]]; then
    sed -e 's/^title.*/title   Ronin (CachyOS + Omarchy)/' "$old_entry" > "$new_entry"
    rm -f "$old_entry"
    log "Entry de boot: $new_entry"
  fi
  if [[ -f /boot/loader/loader.conf ]]; then
    sed -i "s/default ${OLD}\.conf/default ${NAME}.conf/" /boot/loader/loader.conf
  fi
fi

# --- Release / manifiesto / logs --------------------------------------------
if [[ -f /etc/${OLD}-release ]]; then
  sed -e 's/Work OS/Ronin/g; s/work-os/ronin/g' /etc/${OLD}-release > /etc/${NAME}-release
  chmod 644 /etc/${NAME}-release
  rm -f /etc/${OLD}-release
fi
if [[ -d /etc/${OLD} ]]; then
  mkdir -p /etc/${NAME}
  cp -a /etc/${OLD}/. /etc/${NAME}/ 2>/dev/null || true
  rm -rf /etc/${OLD}
fi
if [[ -d /var/log/${OLD} ]]; then
  mkdir -p /var/log/${NAME}
  cp -a /var/log/${OLD}/. /var/log/${NAME}/ 2>/dev/null || true
  rm -rf /var/log/${OLD}
fi
shopt -s nullglob
for f in /var/log/${OLD}-*; do
  mv -f "$f" "${f/${OLD}/${NAME}}"
done
shopt -u nullglob

# --- Generados por hw-adapt (solo comentarios/identidad) ---------------------
for f in /etc/profile.d/ai-gpu-env.sh /root/.config/hypr/hardware-auto.lua \
         /home/*/.config/hypr/hardware-auto.lua /home/*/.config/hypr/hyprland.lua; do
  [[ -f "$f" ]] || continue
  sed -i 's/Work OS/Ronin/g; s/work-os/ronin/g' "$f" 2>/dev/null || true
done

# Los scripts se copiaron después de finalize (que ya había aplicado chmod):
# restaurar permisos restrictivos para que SEC-05 quede en pass.
chmod -R go-rwx /root/build-scripts 2>/dev/null || true

printf 'ronin\n' > "$FLAG"
chmod 644 "$FLAG"
ux_log pass identity "identidad Ronin aplicada" "hostname=$(hostname)" 0
log "RONIN OK (hostname=$(hostname), entry=${NAME}.conf)"
