#!/usr/bin/env bash
# DHCP failover test: create one DHCP client per site, prove that either domain controller can
# go down while clients at BOTH sites still get correct leases, write
# docs/dhcp/failover-test-report.md, destroy the clients. Disruptive: each DC is shut down once
# (and started again) - run it in the lab, not during other work on the DCs.
#
# Usage: scripts/dhcp-failover-test.sh     KEEP=1 leaves the clients running for inspection
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PY="${HOME}/.local/share/pipx/venvs/ansible-core/bin/python" # has PyYAML and pywinrm
REPORT="${REPORT:-${ROOT}/docs/dhcp/failover-test-report.md}"

tf() { TF_ENV=dhcp-test "${ROOT}/scripts/tf.sh" "$@"; }
cleanup() {
  # Whatever happened, both DCs must end up running.
  "${PY}" -I -c "import sys; sys.path.insert(0, '${ROOT}/tests/lib'); import pve; [pve.start(v) for v in (201, 202)]" || true
  if [[ "${KEEP:-0}" == "1" ]]; then
    echo "KEEP=1: clients left running (destroy with: TF_ENV=dhcp-test scripts/tf.sh destroy)"
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
"${PY}" -I "${ROOT}/tests/dhcp/run.py" "${ROOT}/tests/dhcp/failover.yml" "${REPORT}"
