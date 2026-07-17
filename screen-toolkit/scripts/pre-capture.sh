#!/usr/bin/env bash
# pre-capture.sh
# Captures all monitors before region selection.
# Output: /tmp/screen-toolkit-frozen-<timestamp>.png
# Stdout: absolute path to captured image
# Exit code: 0 = success, 1 = grim failed

set -euo pipefail

command -v grim >/dev/null 2>&1 || {
  echo "ERROR: grim not found" >&2
  exit 1
}

timestamp=$(date +%s%N)
output="/tmp/screen-toolkit-frozen-${timestamp}.png"

grim "$output" 2>/dev/null || {
  echo "ERROR: grim capture failed" >&2
  exit 1
}

echo "$output"
