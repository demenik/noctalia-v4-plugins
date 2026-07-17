#!/usr/bin/env bash
# pre-capture.sh
# Captures each output separately before region selection.
# Outputs: /tmp/screen-toolkit-frozen-<timestamp>-<output>.png
# Stdout: JSON object mapping output names to file paths
#   e.g. {"eDP-1":"/tmp/...-eDP-1.png","HDMI-A-1":"/tmp/...-HDMI-A-1.png"}
#   or {"all":"/tmp/...-all.png"} as fallback
# Exit code: 0 = success, 1 = grim failed

set -euo pipefail

command -v grim >/dev/null 2>&1 || {
  echo "ERROR: grim not found" >&2
  exit 1
}

timestamp=$(date +%s%N)
TMPDIR="/tmp"

outputs=""

# Try wlr-randr first (most reliable)
if command -v wlr-randr >/dev/null 2>&1; then
  outputs=$(wlr-randr 2>/dev/null | grep -E '^[A-Za-z]' | awk '{print $1}' | tr '\n' ' ')
fi

# Fallback: grim -l
if [ -z "${outputs// /}" ]; then
  outputs=$(grim -l 2>/dev/null | tr '\n' ' ' || true)
fi

if [ -n "${outputs// /}" ]; then
  result="{"
  first=true
  for output in $outputs; do
    [ -z "$output" ] && continue
    file="${TMPDIR}/screen-toolkit-frozen-${timestamp}-${output}.png"
    grim -o "$output" "$file" 2>/dev/null ||
      {
        echo "ERROR: grim -o $output failed" >&2
        exit 1
      }
    $first || result+=","
    first=false
    result+="\"${output}\":\"${file}\""
  done
  result+="}"
  echo "$result"
else
  file="${TMPDIR}/screen-toolkit-frozen-${timestamp}-all.png"
  grim "$file" 2>/dev/null || {
    echo "ERROR: grim capture failed" >&2
    exit 1
  }
  echo "{\"all\":\"${file}\"}"
fi
