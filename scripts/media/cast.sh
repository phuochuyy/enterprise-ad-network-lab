#!/usr/bin/env bash
# Record a terminal session with asciinema into docs/media/NN-<name>.cast
#
# Usage:
#   cast.sh <name>                 interactive shell, exit to finish
#   cast.sh <name> -- <command>    record a single command (e.g. terraform apply)
set -euo pipefail
# shellcheck source=scripts/media/_common.sh
source "$(dirname "$0")/_common.sh"
need asciinema

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <name> [-- command...]"
name="$(slug "$1")"; shift
out="${MEDIA_DIR}/$(next_seq)-${name}.cast"

args=(rec --overwrite --idle-time-limit 2 --title "${name}")
if [[ "${1:-}" == "--" ]]; then
  shift
  args+=(--command "$*")
fi
asciinema "${args[@]}" "${out}"
echo "${out#"${REPO_ROOT}/"}"
