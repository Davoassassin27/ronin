#!/usr/bin/env bash
# =============================================================================
# F6 - Suite de verificación / aceptación
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_root
require_installed
load_config
make_report_dir

# Salida de pacman/systemd estable: con es_AR, pacman traduce "Architecture"
# a "Arquitectura" y checks como REPO-03 daban falso negativo.
export LC_ALL=C

EXPECT_ROOT_DISABLED="${EXPECT_ROOT_DISABLED:-0}"
JSON_OUT="${VERIFY_JSON:-/var/log/ronin-verify.json}"
TXT_OUT="${VERIFY_TXT:-/var/log/ronin-verify.txt}"

# Trazabilidad: cualquier fallo inesperado también queda en el log UX.
trap 'ux_log fail verify "error inesperado en la verificacion" "$BASH_COMMAND" $? >/dev/null 2>&1 || true' ERR

PASS=0
FAIL=0
WARN=0
RESULTS=()

add_result() {
  local id="$1" status="$2" detail="$3"
  case "$status" in
    pass) PASS=$((PASS + 1)) ;;
    fail) FAIL=$((FAIL + 1)) ;;
    warn) WARN=$((WARN + 1)) ;;
  esac
  RESULTS+=("$(jq -nc --arg id "$id" --arg status "$status" --arg detail "$detail" \
    '{id:$id,status:$status,detail:$detail}')")
  printf '%-9s %-8s %s\n' "$id" "${status^^}" "$detail"
  case "$status" in
    pass) ux_log pass verify "$id: $detail" "" 0 ;;
    warn) ux_log warn verify "$id: $detail" "" 0 ;;
    fail) ux_log fail verify "$id: $detail" "" 1 ;;
  esac
}

run_check() {
  local id="$1" desc="$2" cmd="$3"
  local out
  if out=$(bash -c "$cmd" 2>&1); then
    add_result "$id" pass "$desc"
  else
    local last
    last=$(printf '%s' "$out" | tail -n1 | cut -c1-180)
    add_result "$id" fail "$desc${last:+: $last}"
  fi
}

run_warn() {
  local id="$1" desc="$2" cmd="$3"
  local out
  if out=$(bash -c "$cmd" 2>&1); then
    add_result "$id" pass "$desc"
  else
    local last
    last=$(printf '%s' "$out" | tail -n1 | cut -c1-180)
    add_result "$id" warn "$desc${last:+: $last}"
  fi
}

echo "Ronin - verificación ($(date --iso-8601=seconds))"
echo "Host: $(hostname) / kernel: $(uname -r)"
echo "----------------------------------------------------------------"

# --- Boot --------------------------------------------------------------------
run_check BOOT-01 'Fallback EFI existe' 'test -f /boot/EFI/BOOT/BOOTX64.EFI'
run_check BOOT-02 'systemd-boot operativo' 'bootctl status >/dev/null'
run_check BOOT-03 'Entry root=UUID' 'grep -q "root=UUID=" /boot/loader/entries/ronin.conf'
run_check BOOT-04 'Kernel linux-cachyos' 'pacman -Q linux-cachyos >/dev/null'
run_check BOOT-05 'mkinitcpio -P' 'mkinitcpio -P >/dev/null 2>&1'
run_warn  BOOT-06 'Microcode cargado' 'journalctl -k --no-pager | grep -qi microcode'
run_check BOOT-07 'Secure Boot deshabilitado' 'bootctl status | grep -q "Secure Boot: disabled"'

# --- Repositorios ------------------------------------------------------------
run_check REPO-01 'Repo CachyOS configurado' 'grep -q "^\[cachyos\]" /etc/pacman.conf'
run_check REPO-02 'Repo CachyOS x86-64-v3 configurado' 'grep -q "^\[cachyos-v3\]" /etc/pacman.conf'
run_check REPO-03 'Paquetes base x86-64-v3' 'pacman -Qi glibc 2>/dev/null | grep -q "Architecture.*x86_64_v3"'

# --- Filesystems -------------------------------------------------------------
# Detección por disco real de root: funciona igual en /dev/vda (build, 2 parts)
# y en /dev/nvme0n1 (migrado, 3 parts con DATOS exFAT en la primera).
if detect_disk_layout; then
  ux_log info layout "disco detectado" \
    "disk=$DETECT_DISK layout=$DETECT_LAYOUT parts=$DETECT_PART_COUNT" 0
else
  ux_fail layout "no se pudo detectar el disco de root" "" 1 || true
fi

if [[ "${DETECT_LAYOUT:-build}" == "migrated" ]]; then
  run_check FS-01 'GPT con 3 particiones (migrado)' 'test "$DETECT_PART_COUNT" -eq 3'
  run_check FS-02 'DATOS exFAT' 'blkid -s TYPE -o value "$DETECT_DATA_DEV" | grep -qx exfat'
  run_check FS-03 'Root Btrfs (p3)' 'blkid -s TYPE -o value "$DETECT_ROOT_DISK_DEV" | grep -qx btrfs'
else
  run_check FS-01 'GPT con 2 particiones (build)' 'test "$DETECT_PART_COUNT" -eq 2'
  run_check FS-02 'ESP FAT32' 'blkid -s TYPE -o value "$DETECT_ESP_DEV" | grep -qx vfat'
  run_check FS-03 'Root Btrfs' 'blkid -s TYPE -o value "$DETECT_ROOT_DISK_DEV" | grep -qx btrfs'
fi
run_check FS-04 'Sin swap física (solo zram)' '! lsblk -o NAME,FSTYPE -n | awk "\$2==\"swap\" && \$1 !~ /^zram/ {f=1} END{exit f?0:1}"'
run_check FS-05 '6 subvolúmenes' 'for s in @ @home @var_cache @var_log @docker @snapshots; do btrfs subvolume list / | grep -q "$s" || exit 1; done'
run_check FS-06 'Root en subvol @' 'findmnt -no OPTIONS / | grep -q "subvol=/@"'
run_check FS-07 'Opciones Btrfs root' 'findmnt -no OPTIONS / | grep -q "compress=zstd:3" && findmnt -no OPTIONS / | grep -q "discard=async"'
run_check FS-08 'Docker nodatacow (chattr +C)' 'lsattr -d /var/lib/docker 2>/dev/null | grep -q "C"'
run_check FS-09 'fstab sin PARTUUID' '! grep -v "^#" /etc/fstab | grep -q PARTUUID'
run_check FS-10 'fstab válido' 'findmnt --verify >/dev/null 2>&1'
run_check FS-11 'zram activo' 'zramctl | grep -q zram0 && swapon --show | grep -q /dev/zram0'
run_warn  FS-12 'Espacio root > 20 GiB' 'test "$(df -BG --output=avail / | tail -n1 | tr -dc "0-9")" -gt 20'

# --- Servicios ---------------------------------------------------------------
for svc in NetworkManager sshd docker ollama hw-adapt sddm ufw systemd-timesyncd; do
  run_check "SVC-${svc}" "enabled: $svc" "systemctl is-enabled $svc >/dev/null"
done
run_check SVC-09 'docker/ollama/NM activos' 'systemctl is-active docker ollama NetworkManager >/dev/null'
run_check SVC-10 'hw-adapt ejecutado' 'systemctl is-active hw-adapt >/dev/null'

# --- Hardware / portabilidad -------------------------------------------------
run_check HW-01 'hw-adapt JSON válido' 'jq -e . /var/log/hw-adapt-last.json >/dev/null'
run_check HW-02 'hw-adapt schema' 'jq -e ".schema == 1 and .board != null and .cpu != null and (.gpus|type==\"array\")" /var/log/hw-adapt-last.json >/dev/null'
run_check HW-03 'Board coincide con DMI' 'bn=$(cat /sys/class/dmi/id/board_name 2>/dev/null); jb=$(jq -r .board /var/log/hw-adapt-last.json); [ "$jb" = "$bn" ] || { [ -z "$bn" ] && [ "$jb" = unknown ]; }'
run_check HW-04 'Perfil coherente' 'p=$(jq -r .profile /var/log/hw-adapt-last.json); [[ "$p" == performance || "$p" == balanced || "$p" == power-saver ]]'
run_check HW-05 'Log hw-adapt existe' 'test -s /var/log/hw-adapt.log'
run_check HW-06 'ai-gpu-env sintaxis' 'bash -n /etc/profile.d/ai-gpu-env.sh'
run_check HW-07 'Hyprland Lua source hardware' "grep -q 'require(\"hypr.hardware-auto\")' /home/$TARGET_USER/.config/hypr/hyprland.lua"
# Los drivers de storage/USB pueden estar como .ko en el initramfs O compilados
# dentro del kernel (CONFIG_*=y). En linux-cachyos nvme/ahci/uas suelen ser
# built-in, así que exigir un .ko daba un falso fallo. Aceptar ambos estados.
kernel_storage_ready() {
  local pattern="$1" configs="$2" img=/boot/initramfs-linux-cachyos.img config
  lsinitcpio "$img" 2>/dev/null | grep -Eq "$pattern" && return 0
  for config in /proc/config.gz "/boot/config-$(uname -r)"; do
    [[ -r "$config" ]] || continue
    if [[ "$config" == *.gz ]]; then
      zgrep -Eq "$configs" "$config" && return 0
    else
      grep -Eq "$configs" "$config" && return 0
    fi
  done
  return 1
}
export -f kernel_storage_ready
run_check HW-08 'Initramfs UAS/USB (módulo o built-in)' 'kernel_storage_ready "/(uas|usb[-_]storage)\.ko" "CONFIG_USB_(UAS|STORAGE)=y"'
run_check HW-09 'Initramfs NVMe/AHCI (módulo o built-in)' 'kernel_storage_ready "/(nvme|xhci[-_]pci|ahci)\.ko" "CONFIG_(NVME|XHCI_PCI|AHCI)=y"'
run_check HW-10 'Initramfs GPUs' 'lsinitcpio /boot/initramfs-linux-cachyos.img | grep -Eq "/(amdgpu|i915|xe|nouveau)\.ko"'
run_check HW-13 'Omarchy bootstrap accesible' 'test -f /usr/share/omarchy/default/hypr/bootstrap.lua && test -f /usr/share/omarchy/default/bash/env-bootstrap'
run_check HW-14 'OMARCHY_PATH en entorno' 'grep -q "^OMARCHY_PATH=" /etc/environment || grep -q "OMARCHY_PATH" /etc/profile.d/omarchy.sh'
run_check HW-15 'Shell Omarchy instalado' 'command -v omarchy-launch-shell >/dev/null && test -f /usr/share/omarchy/shell/shell.qml'

# Cambio de placa simulado
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
mkdir -p "$TMP_TEST/state"
jq -n '{board:"OLD",product:"OLD"}' > "$TMP_TEST/state/state.json"
if env HW_ADAPT_DRY_RUN=1 HW_ADAPT_FAKE_BOARD=NEW \
  HW_ADAPT_STATE_DIR="$TMP_TEST/state" HW_ADAPT_LOG_FILE="$TMP_TEST/log" \
  HW_ADAPT_JSON_FILE="$TMP_TEST/json" HW_ADAPT_ENV_FILE="$TMP_TEST/env" \
  HW_ADAPT_HYPR_FILE="$TMP_TEST/hypr" /usr/local/bin/hw-adapt.sh >/dev/null 2>&1; then
  run_check HW-11 'Cambio de placa detectado' "jq -e '.changed_board == true' '$TMP_TEST/json' >/dev/null"
else
  add_result HW-11 fail 'hw-adapt no ejecutó en test de placa'
fi
run_check HW-12 'Modo laptop simulado' "env HW_ADAPT_DRY_RUN=1 HW_ADAPT_FAKE_BATTERY=1 HW_ADAPT_FAKE_AC=0 HW_ADAPT_STATE_DIR='$TMP_TEST/state2' HW_ADAPT_LOG_FILE='$TMP_TEST/log2' HW_ADAPT_JSON_FILE='$TMP_TEST/json2' HW_ADAPT_ENV_FILE='$TMP_TEST/env2' HW_ADAPT_HYPR_FILE='$TMP_TEST/hypr2' /usr/local/bin/hw-adapt.sh >/dev/null 2>&1 && jq -e '.mode == \"laptop\"' '$TMP_TEST/json2' >/dev/null"

# --- Dev / AI / Gaming -------------------------------------------------------
run_check DEV-01 'Toolchain (usuario)' "sudo -u $TARGET_USER -H bash -lc 'cd ~ && uv --version && rustc --version && go version && node --version' >/dev/null 2>&1"
run_check DEV-02 'DB clients' 'duckdb --version >/dev/null && sqlite3 --version >/dev/null'
run_check DEV-03 'Docker root dir' 'test "$(docker info --format "{{.DockerRootDir}}" 2>/dev/null)" = "/var/lib/docker"'
run_check DEV-04 'Docker hello-world' 'timeout 120 docker run --rm hello-world >/dev/null 2>&1'
run_check DEV-05 'Usuario en grupo docker' "id -nG $TARGET_USER | grep -qw docker"
run_check AI-01 'Ollama activo' 'systemctl is-active ollama >/dev/null'
run_check AI-02 'Ollama API' 'curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null'
run_check AI-03 'Directorio de modelos' "test -d /home/$TARGET_USER/ai-models/ollama"
# Sin VK_ICD_FILENAMES para que el loader escanee /usr/share/vulkan/icd.d;
# así el check no depende de un env viejo o de una ruta renombrada por Mesa.
run_warn  AI-04 'Vulkan' 'env -u VK_ICD_FILENAMES vulkaninfo --summary >/dev/null 2>&1'
run_check AI-05 'Monitores GPU' 'command -v nvtop >/dev/null && command -v radeontop >/dev/null'
run_check GAME-01 'Gaming meta instalado' 'pacman -Q cachyos-gaming-meta >/dev/null 2>&1 || pacman -Q steam >/dev/null 2>&1'
run_check GAME-02 'Sin launchers al boot' '! systemctl list-unit-files --state=enabled | grep -Eiq "steam|heroic|gog|bottles|lutris"'
run_check GAME-03 'MangoHud' 'command -v mangohud >/dev/null'

# --- Seguridad ---------------------------------------------------------------
if [[ "$EXPECT_ROOT_DISABLED" == "1" ]]; then
  run_check SEC-01 'Root SSH deshabilitado' 'sshd -T | grep -Eiq "^permitrootlogin no"'
else
  run_check SEC-01 'Root SSH solo clave' 'sshd -T | grep -Eiq "^permitrootlogin (no|prohibit-password)"'
fi
run_check SEC-02 'Password SSH off' 'sshd -T | grep -Eiq "^passwordauthentication no"'
run_check SEC-03 'UFW activo' 'ufw status | grep -q "Status: active"'
run_check SEC-04 'sysctl hardening' 'test "$(sysctl -n kernel.kptr_restrict)" = 2 && test "$(sysctl -n kernel.dmesg_restrict)" = 1'
run_warn  SEC-05 'build-scripts sin lectura pública' '! find /root/build-scripts -perm -o+r | grep -q .'
run_check SEC-06 'Credenciales 600' 'f=/root/build-credentials.txt; [[ ! -e "$f" ]] || [[ "$(stat -c %a "$f")" = 600 ]]'
run_check SEC-07 'sudoers válido' 'visudo -cf /etc/sudoers >/dev/null'

# --- Reporte -----------------------------------------------------------------
echo "----------------------------------------------------------------"
printf 'Resumen: %d PASS, %d WARN, %d FAIL\n' "$PASS" "$WARN" "$FAIL"
ux_log info verify "resumen" "pass=$PASS warn=$WARN fail=$FAIL" 0

CHECKS_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
jq -n \
  --arg timestamp "$(timestamp)" \
  --arg hostname "$(hostname)" \
  --arg kernel "$(uname -r)" \
  --argjson pass "$PASS" \
  --argjson warn "$WARN" \
  --argjson fail "$FAIL" \
  --argjson checks "$CHECKS_JSON" \
  '{schema:1, timestamp:$timestamp, hostname:$hostname, kernel:$kernel,
    summary:{pass:$pass, warn:$warn, fail:$fail}, checks:$checks}' > "$JSON_OUT"

{
  echo "Ronin verify - $(timestamp)"
  echo "PASS=$PASS WARN=$WARN FAIL=$FAIL"
  printf '%s\n' "${RESULTS[@]}" | jq -r '"\(.id) \(.status) \(.detail)"'
} > "$TXT_OUT"

log "Reporte: $JSON_OUT"
if (( FAIL > 0 )); then
  log "VERIFY FAIL"
  exit 1
fi
log "VERIFY OK"
