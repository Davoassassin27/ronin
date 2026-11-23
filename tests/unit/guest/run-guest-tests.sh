#!/usr/bin/env bash
# =============================================================================
# Ronin - unit tests de guest (sin hardware): detección de disco, layout
# migrado/build y trazabilidad UX. Todo resultado se escribe también al log UX.
# Uso: bash tests/unit/guest/run-guest-tests.sh [ruta-a-build/guest/lib.sh]
# =============================================================================
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${1:-$REPO_ROOT/../build/guest/lib.sh}"
LIB="$(cd -- "$(dirname "$LIB")" && pwd)/$(basename "$LIB")"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export UX_LOG_FILE="${UX_LOG_FILE:-$TMP/ux-trace.jsonl}"
export MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"

# --- Mocks de comandos de disco ---------------------------------------------
cat > "$MOCK_BIN/findmnt" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"SOURCE /"* ]] || exit 1
case "${MOCK_LAYOUT:-build}" in
  migrated) echo '/dev/nvme0n1p3[/@]' ;;
  *)        echo '/dev/vda2[/@]' ;;
esac
EOF
cat > "$MOCK_BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *"-no PKNAME"* ]]; then
  case "${MOCK_LAYOUT:-build}" in migrated) echo nvme0n1 ;; *) echo vda ;; esac
  exit 0
fi
if [[ "$args" == *"-lnpo NAME"* ]]; then
  case "${MOCK_LAYOUT:-build}" in
    migrated) printf '/dev/nvme0n1\n/dev/nvme0n1p1\n/dev/nvme0n1p2\n/dev/nvme0n1p3\n' ;;
    *)        printf '/dev/vda\n/dev/vda1\n/dev/vda2\n' ;;
  esac
  exit 0
fi
exit 1
EOF
cat > "$MOCK_BIN/blkid" <<'EOF'
#!/usr/bin/env bash
dev="${@: -1}"
case "$dev" in
  /dev/nvme0n1p1) echo exfat ;;
  /dev/nvme0n1p2) echo vfat  ;;
  /dev/nvme0n1p3) echo btrfs ;;
  /dev/vda1)      echo vfat  ;;
  /dev/vda2)      echo btrfs ;;
  *) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/date" <<'EOF'
#!/usr/bin/env bash
echo '2026-11-19T00:00:00+00:00'
EOF
chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"

# shellcheck source=../../build/guest/lib.sh
. "$LIB"

PASS=0
FAIL=0
RESULTS=()

report() {
  local status="$1" name="$2" detail="${3:-}"
  RESULTS+=("$status $name $detail")
  if [[ "$status" == PASS ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  printf '%-4s %s %s\n' "$status" "$name" "$detail"
  local lvl=pass; [[ "$status" == FAIL ]] && lvl=fail
  ux_log "$lvl" unittest "$name" "$detail" "$([[ "$status" == PASS ]] && echo 0 || echo 1)"
}

check_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then report PASS "$1" "ok"; else report FAIL "$1" "expected=$2 got=$3"; fi
}

# --- Test 1: layout de build -------------------------------------------------
export MOCK_LAYOUT=build
if detect_disk_layout; then
  check_eq layout_build_disk       /dev/vda  "$DETECT_DISK"
  check_eq layout_build_kind       build     "$DETECT_LAYOUT"
  check_eq layout_build_parts      2         "$DETECT_PART_COUNT"
  check_eq layout_build_esp        /dev/vda1 "$DETECT_ESP_DEV"
  check_eq layout_build_root       /dev/vda2 "$DETECT_ROOT_DISK_DEV"
else
  report FAIL layout_build "detect_disk_layout falló"
fi

# --- Test 2: layout migrado (NVMe, 3 particiones) ---------------------------
export MOCK_LAYOUT=migrated
if detect_disk_layout; then
  check_eq layout_migrated_disk    /dev/nvme0n1    "$DETECT_DISK"
  check_eq layout_migrated_kind    migrated        "$DETECT_LAYOUT"
  check_eq layout_migrated_parts   3               "$DETECT_PART_COUNT"
  check_eq layout_migrated_datos   /dev/nvme0n1p1  "$DETECT_DATA_DEV"
  check_eq layout_migrated_esp     /dev/nvme0n1p2  "$DETECT_ESP_DEV"
  check_eq layout_migrated_root    /dev/nvme0n1p3  "$DETECT_ROOT_DISK_DEV"
else
  report FAIL layout_migrated "detect_disk_layout falló"
fi

# --- Test 3: ux_log escribe JSONL con nivel fail -----------------------------
: > "$UX_LOG_FILE"
ux_log fail mount "fallo simulado de montaje" "dev=/dev/nvme0n1p3" 32
if grep -q '"level":"fail"' "$UX_LOG_FILE" && grep -q 'fallo simulado de montaje' "$UX_LOG_FILE"; then
  report PASS ux_log_fail "jsonl escrito"
else
  report FAIL ux_log_fail "no se escribió el JSONL"
fi

# --- Test 4: ux_run captura código y registra fallo --------------------------
: > "$UX_LOG_FILE"
set +e
ux_run mount "montar fallido" bash -c 'echo error_de_montaje >&2; exit 7' >/dev/null
rc=$?
set -e
check_eq ux_run_exit 7 "$rc"
if grep -q '"code":7' "$UX_LOG_FILE" && grep -q 'error_de_montaje' "$UX_LOG_FILE"; then
  report PASS ux_run_trace "fallo trazado"
else
  report FAIL ux_run_trace "falta traza del fallo"
fi

# --- Test 5: ux_fail devuelve no-cero y deja rastro --------------------------
: > "$UX_LOG_FILE"
set +e
ux_fail mount "no se pudo montar" "ctx=test" 4 >/dev/null 2>&1
rc=$?
set -e
check_eq ux_fail_exit 4 "$rc"
grep -q '"level":"fail"' "$UX_LOG_FILE" && report PASS ux_fail_trace "ok" || report FAIL ux_fail_trace "sin traza"

# --- Test 6: 90-verify no debe hardcodear /dev/vda3 --------------------------
VERIFY="$REPO_ROOT/../build/guest/90-verify.sh"
if grep -q '/dev/vda3' "$VERIFY" 2>/dev/null; then
  report FAIL verify_no_hardcoded_vda "sigue habiendo /dev/vda3"
else
  report PASS verify_no_hardcoded_vda "ok"
fi

# --- Resultado ---------------------------------------------------------------
printf '%s\n' '---'
printf 'UNIT PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
ux_log info unittest "resumen unit tests" "pass=$PASS fail=$FAIL" 0
if [[ -n "${UNIT_JSON:-}" ]]; then
  {
    printf '{"pass":%d,"fail":%d,"tests":[' "$PASS" "$FAIL"
    for i in "${!RESULTS[@]}"; do
      IFS=' ' read -r s n d <<< "${RESULTS[$i]}"
      [[ $i -gt 0 ]] && printf ','
      printf '{"status":"%s","name":"%s","detail":"%s"}' "$s" "$n" "$d"
    done
    printf ']}\n'
  } > "$UNIT_JSON"
fi
(( FAIL == 0 ))
