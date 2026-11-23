#!/usr/bin/env bash
# =============================================================================
# Ronin - lint para CI Linux
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0

echo "== bash -n =="
while IFS= read -r file; do
  if bash -n "$file"; then
    echo "  [OK]   $file"
  else
    echo "  [FAIL] $file"
    fail=1
  fi
done < <(find . -path ./.git -prune -o -name '*.sh' -type f -print)

if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck =="
  if shellcheck -S warning -x $(find build/guest -name '*.sh' -type f) build/guest/lib.sh 2>&1; then
    echo "  [OK] shellcheck"
  else
    echo "  [FAIL] shellcheck"
    fail=1
  fi
else
  echo "  [WARN] shellcheck no instalado"
fi

echo "== JSON =="
while IFS= read -r file; do
  if jq -e . "$file" >/dev/null 2>&1; then
    echo "  [OK]   $file"
  else
    echo "  [FAIL] $file"
    fail=1
  fi
done < <(find . -path ./.git -prune -o -name '*.json' -type f -print)

if (( fail > 0 )); then
  echo "Lint FAIL"
  exit 1
fi
echo "Lint OK"
