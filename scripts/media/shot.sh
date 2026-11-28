#!/usr/bin/env bash
# Take a screenshot into docs/media/NN-<name>.png
#
# Usage: shot.sh <name> [--window "<title regex>"|--focused|--select|--full] [--delay N]
#   --window   one top-level window matched by title, e.g. "VM 9001" (preferred: nothing
#              else on the desktop can leak into the image; the window must not be covered)
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
window=""
delay=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --window) window="$2"; shift ;;
    --focused) mode=(-u) ;;
    --select) mode=(-s -f) ;;
    --full) mode=() ;;
    --delay) delay="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

out="${MEDIA_DIR}/$(next_seq)-${name}.png"
if [[ -n "${window}" ]]; then
  need xwininfo; need xwd; need ffmpeg
  wid="$(xwininfo -root -tree | grep -E "\"[^\"]*${window}[^\"]*\":" | grep -v ' 1x1+' | head -1 | awk '{print $1}')"
  [[ -n "${wid}" ]] || die "no window title matches: ${window}"
  sleep "${delay}"
  # Without a compositor xwd copies whatever is on screen in the window's area, so a covered
  # window would capture the windows on top of it (e.g. a personal terminal). Refuse instead.
  need xprop
  active="$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')"
  if (( active != wid )); then
    die "window '${window}' is not in front - click it (bring it to the top), then retry"
  fi
  xwd -silent -id "${wid}" | ffmpeg -hide_banner -loglevel error -y -f xwd_pipe -i - "${out}"
else
  scrot "${mode[@]}" -d "${delay}" -o "${out}"
fi
echo "${out#"${REPO_ROOT}/"}"
