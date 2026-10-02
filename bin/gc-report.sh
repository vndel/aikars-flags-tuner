#!/usr/bin/env bash
#
# gc-report.sh — summarise GC behaviour from a Paper server log
#
# Reads -Xlog:gc output and reports pause distribution. The number that
# matters is not average pause but the count of pauses above 50ms: that
# is the tick budget, so anything longer is a visible stutter.
#
set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"

usage() {
  printf 'Usage: %s <gc.log>\n' "$SCRIPT_NAME" >&2
}

main() {
  local log="${1:-}"
  [[ -n "$log" ]] || { usage; exit 1; }
  [[ -r "$log" ]] || { printf 'cannot read %s\n' "$log" >&2; exit 1; }

  printf '── GC summary: %s ──\n' "$log"

  local total
  total=$(grep -cE 'Pause (Young|Full|Mark)' "$log" || true)
  printf 'collections        : %s\n' "${total:-0}"

  if [[ "${total:-0}" -eq 0 ]]; then
    printf 'no GC records found; was -Xlog:gc enabled?\n'
    return 0
  fi

  # Pause durations appear as a trailing "123.456ms" field.
  grep -oE '[0-9]+\.[0-9]+ms' "$log" \
    | tr -d 'ms' \
    | awk '
        { v[NR] = $1; sum += $1; if ($1 > max) max = $1; if ($1 > 50) over++ }
        END {
          if (NR == 0) exit
          n = asort(v)
          printf "mean pause         : %.2fms\n", sum / NR
          printf "p95 pause          : %.2fms\n", v[int(n * 0.95)]
          printf "max pause          : %.2fms\n", max
          printf "pauses over 50ms   : %d (%.1f%%)\n", over, (over / NR) * 100
          if (over / NR > 0.01)
            printf "\nverdict: >1%% of pauses exceed the tick budget.\n          Consider a larger young gen or ZGC.\n"
          else
            printf "\nverdict: pause profile is within the tick budget.\n"
        }' 2>/dev/null \
    || printf 'awk lacks asort(); install gawk for percentile output\n' >&2
}

main "$@"
