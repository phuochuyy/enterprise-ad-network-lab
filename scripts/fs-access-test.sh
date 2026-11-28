#!/usr/bin/env bash
# File share access test: create one Linux client per site in the Users VLANs, prove the AGDLP
# permissions and access-based enumeration with real domain users over SMB through the DFS
# namespace, write docs/fileserver/access-test-report.md, destroy the clients.
#
# Usage: scripts/fs-access-test.sh     KEEP=1 leaves the clients running for inspection
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PY="${HOME}/.local/share/pipx/venvs/ansible-core/bin/python" # has PyYAML
REPORT="${REPORT:-${ROOT}/docs/fileserver/access-test-report.md}"

tf() { TF_ENV=fs-test "${ROOT}/scripts/tf.sh" "$@"; }
cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    echo "KEEP=1: clients left running (destroy with: TF_ENV=fs-test scripts/tf.sh destroy)"
  else
    echo "--- destroying clients"
    tf destroy -auto-approve -input=false -no-color >/dev/null
  fi
}
trap cleanup EXIT

echo "--- creating clients"
tf init -input=false -no-color >/dev/null
tf apply -auto-approve -input=false -no-color | grep -E '^(Apply complete|Plan:)' || true

mkdir -p "$(dirname "${REPORT}")"
"${PY}" -I "${ROOT}/tests/fileserver/run.py" "${ROOT}/tests/fileserver/access.yml" "${REPORT}"
