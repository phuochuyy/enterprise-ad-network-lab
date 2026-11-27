#!/usr/bin/env bash
# Shared helpers for evidence capture scripts. Sourced, not executed.
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
MEDIA_DIR="${REPO_ROOT}/docs/media"
STATE_DIR="$(git rev-parse --git-dir)/media-state" # inside .git, never committed
export DISPLAY="${DISPLAY:-:0}"
mkdir -p "${MEDIA_DIR}" "${STATE_DIR}"

die() { echo "error: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed"; }

# slug "Live Migration #1" -> live-migration-1
slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Next sequence number so files sort in the order they were captured: 01, 02, ...
next_seq() {
  local last
  last="$(find "${MEDIA_DIR}" -maxdepth 1 -type f -regex '.*/[0-9][0-9]-.*' -printf '%f\n' \
    | cut -c1-2 | sort -n | tail -1)"
  printf '%02d' "$((10#${last:-0} + 1))"
}
