#!/usr/bin/env bash
# =============================================================================
# Ronin - hardware adaptation daemon (one-shot, pre-display-manager)
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VERSION="1.0.0"
CONF="/etc/hw-adapt.conf"
STATE_DIR="${HW_ADAPT_STATE_DIR:-/var/lib/hw-adapt}"
LOG_FILE="${HW_ADAPT_LOG_FILE:-/var/log/hw-adapt.log}"
JSON_FILE="${HW_ADAPT_JSON_FILE:-/var/log/hw-adapt-last.json}"
HYPR_FILE="${HW_ADAPT_HYPR_FILE:-}"
ENV_FILE="${HW_ADAPT_ENV_FILE:-/etc/profile.d/ai-gpu-env.sh}"
DRY_RUN="${HW_ADAPT_DRY_RUN:-0}"
SELF_TEST="${HW_ADAPT_SELF_TEST:-0}"
FAKE_BOARD="${HW_ADAPT_FAKE_BOARD:-}"
FAKE_BATTERY="${HW_ADAPT_FAKE_BATTERY:-}"
FAKE_AC="${HW_ADAPT_FAKE_AC:-}"

# Defaults (overridable in /etc/hw-adapt.conf)
HW_ADAPT_USER="${HW_ADAPT_USER:-}"
WRITE_MONITOR_CONFIG="${WRITE_MONITOR_CONFIG:-1}"
AMD_GFX_VERSION="${AMD_GFX_VERSION:-}"
LOW_BATTERY_POWERSAVER="${LOW_BATTERY_POWERSAVER:-1}"
CLEAN_ON_BOARD_CHANGE="${CLEAN_ON_BOARD_CHANGE:-1}"
RESTART_NETWORK_ON_BOARD_CHANGE="${RESTART_NETWORK_ON_BOARD_CHANGE:-0}"

if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  . "$CONF"
fi

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

log_line() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$LOG_FILE"
}

die() {
  log_line "ERROR: $*"
  printf '[hw-adapt] ERROR: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq no está instalado"

read_first() {
  local file="$1" default="${2:-}"
  if [[ -r "$file" ]]; then
    tr -d '\n' < "$file"
  else
    printf '%s' "$default"
  fi
}

json_append() {
  local arr="$1" obj="$2"
  jq -nc --argjson a "$arr" --argjson o "$obj" '$a + [$o]'
}

# --- 1. Detección ------------------------------------------------------------
BOARD=$(read_first /sys/class/dmi/id/board_name unknown)
PRODUCT=$(read_first /sys/class/dmi/id/product_name unknown)
VENDOR=$(read_first /sys/class/dmi/id/sys_vendor unknown)
CHASSIS_RAW=$(read_first /sys/class/dmi/id/chassis_type 0)
BOOT_ID=$(read_first /proc/sys/kernel/random/boot_id unknown)
TS=$(date --iso-8601=seconds)
HOSTNAME=$(hostname 2>/dev/null || echo ronin)

if [[ -n "$FAKE_BOARD" ]]; then
  BOARD="$FAKE_BOARD"
fi

case "$CHASSIS_RAW" in
  8|9|10|14|30|31|32|33) CHASSIS="portable" ;;
  3|4|5|6|7|35|36)      CHASSIS="desktop" ;;
  *)                     CHASSIS="unknown" ;;
esac

CPU_MODEL="unknown"; CPU_CORES=0; CPU_THREADS=0
if command -v lscpu >/dev/null 2>&1; then
  CPU_JSON=$(lscpu -J 2>/dev/null || true)
  if [[ -n "$CPU_JSON" ]]; then
    CPU_MODEL=$(printf '%s' "$CPU_JSON" | jq -r '.lscpu[] | select(.field=="Model name:") | .data' | head -n1)
    CPU_CORES=$(printf '%s' "$CPU_JSON" | jq -r '.lscpu[] | select(.field=="Core(s) per socket:") | .data' | head -n1)
    CPU_THREADS=$(printf '%s' "$CPU_JSON" | jq -r '.lscpu[] | select(.field=="CPU(s):") | .data' | head -n1)
  fi
fi
[[ "$CPU_CORES" =~ ^[0-9]+$ ]] || CPU_CORES=0
[[ "$CPU_THREADS" =~ ^[0-9]+$ ]] || CPU_THREADS=0

MEM_TOTAL_KIB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_TOTAL_BYTES=$(( MEM_TOTAL_KIB * 1024 ))

# --- 2. Batería / AC ---------------------------------------------------------
BATTERY_PRESENT=false
BATTERY_CAPACITY=""
BATTERY_STATUS=""
if [[ "$FAKE_BATTERY" == "1" ]]; then
  BATTERY_PRESENT=true
  BATTERY_CAPACITY=50
  BATTERY_STATUS=Discharging
elif compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
  BATTERY_PRESENT=true
  first_bat=$(compgen -G '/sys/class/power_supply/BAT*' | head -n1)
  BATTERY_CAPACITY=$(read_first "$first_bat/capacity" "")
  BATTERY_STATUS=$(read_first "$first_bat/status" "")
fi

AC_ONLINE=""
if [[ -n "$FAKE_AC" ]]; then
  AC_ONLINE="$FAKE_AC"
else
  for ac in /sys/class/power_supply/A{C,DP}*; do
    [[ -e "$ac" ]] || continue
    AC_ONLINE=$(read_first "$ac/online" "")
    [[ -n "$AC_ONLINE" ]] && break
  done
fi

MODE="desktop"
if [[ "$BATTERY_PRESENT" == "true" || "$CHASSIS" == "portable" ]]; then
  MODE="laptop"
fi

# --- 3. GPUs -----------------------------------------------------------------
GPUS_JSON='[]'
GPU_NAMES=()
if command -v lspci >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pci=$(printf '%s' "$line" | awk '{print $1}')
    desc=$(printf '%s' "$line" | sed -E 's/^[^ ]+ [^:]+: //')
    lower=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
    vendor="Unknown"
    case "$lower" in
      *nvidia*) vendor="NVIDIA" ;;
      *amd*|*advanced\ micro\ devices*|*ati*) vendor="AMD" ;;
      *intel*) vendor="Intel" ;;
    esac
    driver=""
    link="/sys/bus/pci/devices/$pci/driver"
    if [[ -L "$link" ]]; then
      driver=$(basename "$(readlink -f "$link")")
    fi
    vram=0
    if [[ "$vendor" == "AMD" ]]; then
      vram=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | sort -nr | head -n1 || echo 0)
    elif [[ "$vendor" == "NVIDIA" ]] && command -v nvidia-smi >/dev/null 2>&1; then
      vram_mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)
      [[ "$vram_mib" =~ ^[0-9]+$ ]] || vram_mib=0
      vram=$(( vram_mib * 1024 * 1024 ))
    fi
    [[ "$vram" =~ ^[0-9]+$ ]] || vram=0
    obj=$(jq -n --arg pci "$pci" --arg vendor "$vendor" --arg model "$desc" \
      --arg driver "$driver" --argjson vram "$vram" \
      '{pci:$pci, vendor:$vendor, model:$model, driver:$driver, vram_bytes:$vram}')
    GPUS_JSON=$(json_append "$GPUS_JSON" "$obj")
    GPU_NAMES+=("$vendor")
  done < <(lspci -Dnn 2>/dev/null | grep -E 'VGA|3D|Display' || true)
fi

PRIMARY_GPU="Unknown"
for v in "${GPU_NAMES[@]:-}"; do
  case "$v" in
    NVIDIA) PRIMARY_GPU="NVIDIA"; break ;;
    AMD)    PRIMARY_GPU="AMD" ;;
    Intel)  [[ "$PRIMARY_GPU" == "Unknown" ]] && PRIMARY_GPU="Intel" ;;
  esac
done

# --- 4. Perfil ---------------------------------------------------------------
PROFILE="performance"
if [[ "$MODE" == "laptop" ]]; then
  PROFILE="balanced"
  if [[ "$BATTERY_PRESENT" == "true" && "$AC_ONLINE" == "0" && "$LOW_BATTERY_POWERSAVER" == "1" ]]; then
    if [[ "$BATTERY_CAPACITY" =~ ^[0-9]+$ ]] && (( BATTERY_CAPACITY < 15 )); then
      PROFILE="power-saver"
    fi
  fi
fi

ACTIONS_JSON='[]'
add_action() {
  local text="$1"
  ACTIONS_JSON=$(json_append "$ACTIONS_JSON" "$(jq -Rn --arg s "$text" '$s')")
  log_line "$text"
}

if [[ "$DRY_RUN" != "1" ]]; then
  if command -v powerprofilesctl >/dev/null 2>&1; then
    timeout 5 powerprofilesctl set "$PROFILE" >/dev/null 2>&1 && add_action "powerprofilesctl=$PROFILE" \
      || log_line "WARN: powerprofilesctl set $PROFILE falló"
  fi

  # ACPI platform profile, si existe
  PP=/sys/firmware/acpi/platform_profile
  if [[ -w "$PP" ]]; then
    case "$PROFILE" in
      performance) echo performance > "$PP" 2>/dev/null || true ;;
      power-saver) echo low-power > "$PP" 2>/dev/null || true ;;
      *)           echo balanced > "$PP" 2>/dev/null || true ;;
    esac
  fi

  # EPP
  EPP="balance_performance"
  [[ "$PROFILE" == "performance" ]] && EPP="performance"
  [[ "$PROFILE" == "power-saver" ]] && EPP="power"
  for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [[ -w "$f" ]] || continue
    echo "$EPP" > "$f" 2>/dev/null || true
  done

  # Turbo
  TURBO=1
  [[ "$PROFILE" == "power-saver" ]] && TURBO=0
  [[ "$MODE" == "laptop" && "$AC_ONLINE" == "0" && "$PROFILE" == "balanced" ]] && TURBO=0
  if [[ -w /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    [[ "$TURBO" == "1" ]] && echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
    [[ "$TURBO" == "0" ]] && echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
  elif [[ -w /sys/devices/system/cpu/cpufreq/boost ]]; then
    echo "$TURBO" > /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || true
  fi
  add_action "profile=$PROFILE mode=$MODE gpu=$PRIMARY_GPU"
else
  add_action "dry-run profile=$PROFILE mode=$MODE gpu=$PRIMARY_GPU"
fi

# --- 5. Variables de entorno GPU --------------------------------------------
ENV_JSON='{}'
ENV_SCRIPT="# Ronin - generado por hw-adapt.sh en cada boot. No editar a mano.
# GPU primaria: $PRIMARY_GPU - perfil: $PROFILE
"
add_env() {
  local k="$1" v="$2"
  ENV_JSON=$(jq -c --arg k "$k" --arg v "$v" '. + {($k):$v}' <<< "$ENV_JSON")
  printf 'export %s="%s"\n' "$k" "$v" >> "$ENV_SCRIPT.tmp"
}

rm -f "$ENV_SCRIPT.tmp"
printf '%s\n' "$ENV_SCRIPT" > "$ENV_SCRIPT.tmp"

# Mesa nombra los ICD como <vendor>_icd.json; versiones viejas usaban
# <vendor>_icd.x86_64.json. Elegir el que exista evita ERROR_INCOMPATIBLE_DRIVER.
vulkan_icd_path() {
  local vendor="$1" candidate
  for candidate in \
    "/usr/share/vulkan/icd.d/${vendor}_icd.json" \
    "/usr/share/vulkan/icd.d/${vendor}_icd.x86_64.json"; do
    [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

case "$PRIMARY_GPU" in
  AMD)
    add_env AMD_VULKAN_ICD RADV
    icd=$(vulkan_icd_path radeon) && add_env VK_ICD_FILENAMES "$icd"
    add_env LIBVA_DRIVER_NAME radeonsi
    [[ -n "$AMD_GFX_VERSION" ]] && add_env HSA_OVERRIDE_GFX_VERSION "$AMD_GFX_VERSION"
    ;;
  Intel)
    icd=$(vulkan_icd_path intel) && add_env VK_ICD_FILENAMES "$icd"
    if [[ -f /usr/lib/dri/iHD_drv_video.so ]]; then
      add_env LIBVA_DRIVER_NAME iHD
    else
      add_env LIBVA_DRIVER_NAME i965
    fi
    add_env ONEAPI_DEVICE_SELECTOR level_zero:gpu
    ;;
  NVIDIA)
    icd=$(vulkan_icd_path nvidia) && add_env VK_ICD_FILENAMES "$icd"
    add_env __GLX_VENDOR_LIBRARY_NAME nvidia
    add_env LIBVA_DRIVER_NAME nvidia
    ;;
  *)
    add_env LIBGL_ALWAYS_SOFTWARE 1
    ;;
esac
add_env MESA_SHADER_CACHE_MAX_SIZE 2G

if [[ "$DRY_RUN" != "1" ]]; then
  install -m 644 "$ENV_SCRIPT.tmp" "$ENV_FILE"
else
  cp "$ENV_SCRIPT.tmp" "${ENV_FILE}.dry-run"
fi
rm -f "$ENV_SCRIPT.tmp"

# --- 6. Config de Hyprland (Omarchy 4.5 usa Lua: hl.env / hl.monitor) --------
if [[ -z "$HYPR_FILE" ]]; then
  DETECTED_USER="$HW_ADAPT_USER"
  if [[ -z "$DETECTED_USER" ]]; then
    DETECTED_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')
  fi
  if [[ -n "$DETECTED_USER" ]]; then
    DETECTED_HOME=$(getent passwd "$DETECTED_USER" | cut -d: -f6)
    HYPR_FILE="$DETECTED_HOME/.config/hypr/hardware-auto.lua"
  fi
fi

if [[ -n "$HYPR_FILE" && "$DRY_RUN" != "1" ]]; then
  mkdir -p "$(dirname "$HYPR_FILE")"
  {
    echo "-- Ronin - generado por hw-adapt.sh. No editar."
    echo "-- perfil=$PROFILE modo=$MODE gpu=$PRIMARY_GPU"
    jq -r 'to_entries[] | "hl.env(\(.key|@json), \(.value|@json))"' <<< "$ENV_JSON"
    if [[ "$WRITE_MONITOR_CONFIG" == "1" ]]; then
      echo "-- Fallback de monitores; el panel de Omarchy o reglas del usuario pueden sobreescribir."
      echo 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })'
    fi
  } > "$HYPR_FILE"
  chmod 644 "$HYPR_FILE"

  DETECTED_HOME=$(dirname "$(dirname "$(dirname "$HYPR_FILE")")")
  DETECTED_USER=$(stat -c '%U' "$DETECTED_HOME" 2>/dev/null || true)
  if id "$DETECTED_USER" >/dev/null 2>&1; then
    chown "$DETECTED_USER:$DETECTED_USER" "$HYPR_FILE" 2>/dev/null || true
  fi

  HYPR_CONF="$(dirname "$HYPR_FILE")/hyprland.lua"
  if [[ ! -f "$HYPR_CONF" ]]; then
    printf '%s\n' '-- Ronin minimal Hyprland Lua config' 'require("hypr.hardware-auto")' > "$HYPR_CONF"
  fi
  if ! grep -q 'require("hypr.hardware-auto")' "$HYPR_CONF"; then
    printf '\n-- Ronin hardware\nrequire("hypr.hardware-auto")\n' >> "$HYPR_CONF"
  fi
  chown "$DETECTED_USER:$DETECTED_USER" "$HYPR_CONF" 2>/dev/null || true

  # Limpiar el .conf legacy de versiones anteriores del build.
  LEGACY_CONF="$(dirname "$HYPR_FILE")/hardware-auto.conf"
  if [[ -f "$LEGACY_CONF" ]] && grep -q 'Ronin - generado por hw-adapt' "$LEGACY_CONF"; then
    rm -f "$LEGACY_CONF"
  fi
fi

# --- 7. Cambio de placa ------------------------------------------------------
PREV_STATE="$STATE_DIR/state.json"
CHANGED=false
if [[ -f "$PREV_STATE" ]]; then
  PREV_BOARD=$(jq -r '.board // empty' "$PREV_STATE" 2>/dev/null || true)
  PREV_PRODUCT=$(jq -r '.product // empty' "$PREV_STATE" 2>/dev/null || true)
  if [[ -n "$PREV_BOARD" && ( "$PREV_BOARD" != "$BOARD" || "$PREV_PRODUCT" != "$PRODUCT" ) ]]; then
    CHANGED=true
  fi
fi

if [[ "$CHANGED" == "true" ]]; then
  add_action "board-changed from=$PREV_BOARD/$PREV_PRODUCT to=$BOARD/$PRODUCT"
  if [[ "$DRY_RUN" != "1" ]]; then
    if [[ "$CLEAN_ON_BOARD_CHANGE" == "1" ]]; then
      systemctl try-restart bluetooth.service >/dev/null 2>&1 && add_action "bluetooth restarted" || true
      rm -f /var/lib/alsa/asound.state 2>/dev/null && add_action "alsa state cleared" || true
    fi
    if [[ "$RESTART_NETWORK_ON_BOARD_CHANGE" == "1" ]]; then
      systemctl try-restart NetworkManager.service >/dev/null 2>&1 && add_action "NetworkManager restarted" || true
    else
      add_action "network reindex delegated to NetworkManager boot"
    fi
  fi
fi

# --- 8. JSON + estado --------------------------------------------------------
BATTERY_JSON=$(jq -n --arg present "$BATTERY_PRESENT" --arg cap "$BATTERY_CAPACITY" \
  --arg status "$BATTERY_STATUS" \
  '{present:($present=="true"), capacity:(if $cap=="" then null else ($cap|tonumber) end), status:(if $status=="" then null else $status end)}')

CPU_JSON=$(jq -n --arg model "$CPU_MODEL" --argjson cores "$CPU_CORES" --argjson threads "$CPU_THREADS" \
  '{model:$model, cores:$cores, threads:$threads}')

JSON=$(jq -n \
  --arg timestamp "$TS" \
  --arg boot_id "$BOOT_ID" \
  --arg hostname "$HOSTNAME" \
  --arg board "$BOARD" \
  --arg product "$PRODUCT" \
  --arg vendor "$VENDOR" \
  --arg chassis "$CHASSIS" \
  --arg mode "$MODE" \
  --argjson memory_kib "$MEM_TOTAL_KIB" \
  --argjson cpu "$CPU_JSON" \
  --argjson battery "$BATTERY_JSON" \
  --arg ac "$AC_ONLINE" \
  --argjson gpus "$GPUS_JSON" \
  --arg profile "$PROFILE" \
  --argjson env "$ENV_JSON" \
  --arg hypr "$HYPR_FILE" \
  --arg changed "$CHANGED" \
  --argjson actions "$ACTIONS_JSON" \
  --arg version "$VERSION" \
  '{
    schema: 1,
    timestamp: $timestamp,
    boot_id: $boot_id,
    hostname: $hostname,
    board: $board,
    product: $product,
    vendor: $vendor,
    chassis: $chassis,
    mode: $mode,
    memory_kib: $memory_kib,
    cpu: $cpu,
    battery: $battery,
    ac_online: (if $ac=="" then null else ($ac|tonumber==1) end),
    gpus: $gpus,
    profile: $profile,
    env: $env,
    hypr_config: (if $hypr=="" then null else $hypr end),
    changed_board: ($changed=="true"),
    actions: $actions,
    version: $version
  }')

if [[ "$SELF_TEST" == "1" ]]; then
  printf '%s\n' "$JSON"
  printf '%s\n' "$JSON" | jq -e '.schema == 1 and .profile != null and (.gpus|type=="array")' >/dev/null
  exit 0
fi

TMP_JSON="${JSON_FILE}.tmp.$$"
printf '%s\n' "$JSON" > "$TMP_JSON"
chmod 644 "$TMP_JSON"
mv "$TMP_JSON" "$JSON_FILE"

TMP_STATE="${PREV_STATE}.tmp.$$"
jq -n --arg board "$BOARD" --arg product "$PRODUCT" --arg changed "$TS" \
  '{board:$board, product:$product, updated:$changed}' > "$TMP_STATE"
chmod 644 "$TMP_STATE"
mv "$TMP_STATE" "$PREV_STATE"

log_line "JSON=$JSON_FILE changed_board=$CHANGED"

if [[ "${1:-}" == "--stdout" ]]; then
  printf '%s\n' "$JSON"
fi
