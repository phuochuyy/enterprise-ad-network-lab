#!/usr/bin/env bash
# Take a screenshot into docs/media/NN-<name>.png
#
# Usage: shot.sh <name> [--focused|--select|--full] [--delay N]
#   --focused  active window (default)
#   --select   click a window or drag a region
#   --full     whole screen
set -euo pipefail
# shellcheck source=scripts/media/_common.sh
source "$(dirname "$0")/_common.sh"
need scrot

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <name> [--focused|--select|--full] [--delay N]"
name="$(slug "$1")"; shift
mode=(-u)
delay=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --focused) mode=(-u) ;;
    --select) mode=(-s -f) ;;
    --full) mode=() ;;
    --delay) delay="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

out="${MEDIA_DIR}/$(next_seq)-${name}.png"
scrot "${mode[@]}" -d "${delay}" -o "${out}"
echo "${out#"${REPO_ROOT}/"}"
