#!/usr/bin/env bash
# Firewall policy test: create one probe VM per VLAN, prove every expected allow/deny of
# tests/firewall/policy.yml with real traffic, write docs/network/policy-test-report.md,
# destroy the probes.
#
# Usage: scripts/fw-policy-test.sh        KEEP=1 leaves the probes running for inspection
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PY="${HOME}/.local/share/pipx/venvs/ansible-core/bin/python" # has PyYAML
REPORT="${REPORT:-${ROOT}/docs/network/policy-test-report.md}"

tf() { TF_ENV=fw-test "${ROOT}/scripts/tf.sh" "$@"; }
cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    echo "KEEP=1: probes left running (destroy with: TF_ENV=fw-test scripts/tf.sh destroy)"
  else
    echo "--- destroying probes"
    tf destroy -auto-approve -input=false -no-color >/dev/null
  fi
}
trap cleanup EXIT

echo "--- rendering WireGuard client configs (probe rw)"
"${ROOT}/scripts/ansible.sh" playbooks/firewalls-render.yml >/dev/null

echo "--- creating probes"
tf init -input=false -no-color >/dev/null
tf apply -auto-approve -input=false -no-color | grep -E '^(Apply complete|Plan:)' || true

"${PY}" -I "${ROOT}/tests/firewall/run.py" "${ROOT}/tests/firewall/policy.yml" "${REPORT}"
