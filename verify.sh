#!/usr/bin/env bash
#
# verify.sh — lint the scripts and assert the generated flags are correct
#
set -Eeuo pipefail

cd "$(dirname "$0")"

if command -v shellcheck >/dev/null; then
  echo "── shellcheck ──"
  shellcheck bin/*.sh
  echo "clean"
else
  echo "shellcheck not installed; skipping lint" >&2
fi

chmod +x bin/generate-flags.sh

echo
echo "── flag generation ──"

check() {
  local label="$1"; shift
  if "$@"; then printf '  %-34s ok\n' "$label"
  else printf '  %-34s FAILED\n' "$label"; exit 1; fi
}

check "G1 selected at 8GB"      bash -c "bin/generate-flags.sh -m 8  2>/dev/null | grep -q -- '-XX:+UseG1GC'"
check "ZGC selected at 24GB"    bash -c "bin/generate-flags.sh -m 24 2>/dev/null | grep -q -- '-XX:+UseZGC'"
check "generational ZGC enabled" bash -c "bin/generate-flags.sh -m 24 2>/dev/null | grep -q -- '-XX:+ZGenerational'"
check "Xms equals Xmx"          bash -c "o=\$(bin/generate-flags.sh -m 12 2>/dev/null); grep -q -- '-Xms12G' <<<\"\$o\" && grep -q -- '-Xmx12G' <<<\"\$o\""
check "warns above 31GB"        bash -c "bin/generate-flags.sh -m 40 2>&1 >/dev/null | grep -q 'compressed oops'"
check "rejects bad memory"      bash -c "! bin/generate-flags.sh -m abc 2>/dev/null"
check "rejects unknown gc"      bash -c "! bin/generate-flags.sh -m 4 -g nonsense 2>/dev/null"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
check "generated script is valid" bash -c "bin/generate-flags.sh -m 6 -o '$tmp/start.sh' 2>/dev/null && bash -n '$tmp/start.sh'"

echo
echo "verified"
