#!/usr/bin/env bash
# Screen recording with ffmpeg (X11). Produces an MP4 (for GitHub Releases)
# and an optimized GIF (for README) in docs/media.
#
# Usage:
#   rec.sh start <name> [--region]   start recording in the background
#   rec.sh stop                      stop, finalize MP4, build GIF
#   rec.sh status
set -euo pipefail
# shellcheck source=scripts/media/_common.sh
source "$(dirname "$0")/_common.sh"
need ffmpeg

PID_FILE="${STATE_DIR}/rec.pid"
CUR_FILE="${STATE_DIR}/rec.current"
GIF_WIDTH="${GIF_WIDTH:-1280}"
GIF_FPS="${GIF_FPS:-10}"
GIF_MAX_MB=10

is_running() { [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; }

start() {
  [[ $# -ge 1 ]] || die "usage: rec.sh start <name> [--region]"
  is_running && die "a recording is already running ($(cat "${CUR_FILE}"))"
  local base region=()
  base="${MEDIA_DIR}/$(next_seq)-$(slug "$1")"
  [[ "${2:-}" == "--region" ]] && region=(-select_region 1 -show_region 1)

  nohup ffmpeg -hide_banner -loglevel error -y \
    -f x11grab -framerate 30 "${region[@]}" -draw_mouse 1 -i "${DISPLAY}" \
    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -movflags +faststart \
    "${base}.mp4" >"${STATE_DIR}/rec.log" 2>&1 &
  echo $! >"${PID_FILE}"
  echo "${base}" >"${CUR_FILE}"
  sleep 1
  is_running || { cat "${STATE_DIR}/rec.log" >&2; die "ffmpeg failed to start"; }
  echo "recording -> ${base#"${REPO_ROOT}/"}.mp4  (stop with: rec.sh stop)"
}

stop() {
  is_running || die "no recording in progress"
  local pid base
  pid="$(cat "${PID_FILE}")"; base="$(cat "${CUR_FILE}")"
  kill -INT "${pid}"                      # SIGINT lets ffmpeg write the moov atom
  while kill -0 "${pid}" 2>/dev/null; do sleep 0.3; done
  rm -f "${PID_FILE}" "${CUR_FILE}"

  local filters="fps=${GIF_FPS},scale=${GIF_WIDTH}:-1:flags=lanczos"
  ffmpeg -hide_banner -loglevel error -y -i "${base}.mp4" \
    -vf "${filters},palettegen=stats_mode=diff" "${STATE_DIR}/palette.png"
  ffmpeg -hide_banner -loglevel error -y -i "${base}.mp4" -i "${STATE_DIR}/palette.png" \
    -lavfi "${filters} [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "${base}.gif"

  local mb
  mb=$(( $(stat -c %s "${base}.gif") / 1024 / 1024 ))
  echo "mp4: ${base#"${REPO_ROOT}/"}.mp4  (attach to a GitHub Release, not committed)"
  echo "gif: ${base#"${REPO_ROOT}/"}.gif  (${mb} MB)"
  if (( mb >= GIF_MAX_MB )); then
    echo "warning: GIF >= ${GIF_MAX_MB} MB - re-run with GIF_WIDTH=960 GIF_FPS=8 or trim the MP4" >&2
  fi
}

case "${1:-}" in
  start) shift; start "$@" ;;
  stop) stop ;;
  status) if is_running; then echo "recording: $(cat "${CUR_FILE}")"; else echo "idle"; fi ;;
  *) die "usage: rec.sh start <name> [--region] | stop | status" ;;
esac
