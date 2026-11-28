#!/usr/bin/env bash
# Template acceptance test: clone -> boot -> verify from the outside -> destroy.
#
# Usage: scripts/smoke-test.sh <template_vm_id> [win11]
#   KEEP=1  leave the clone running for inspection
#
# Passes when the clone comes up with the cloud-init hostname and static IP, WinRM answers
# over HTTPS (5986) with NTLM, Basic/unencrypted are off and plain HTTP (5985) is closed -
# exactly how Ansible will reach real VMs.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SECRETS_FILE="${SECRETS_FILE:-${HOME}/.config/lab/secrets.json}"
PY="${HOME}/.local/share/pipx/venvs/ansible-core/bin/python" # has pywinrm
TEST_IP="10.10.10.60"
EXPECTED_HOST="HQ-TST01"

template="${1:?usage: smoke-test.sh <template_vm_id> [win11]}"
extra=()
[[ "${2:-}" == "win11" ]] && extra=(-var tpm=true -var disk_gb=64)

tf() { TF_ENV=template-smoke "${ROOT}/scripts/tf.sh" "$@"; }
cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    echo "KEEP=1: clone left running (destroy with: TF_ENV=template-smoke scripts/tf.sh destroy -var template_vm_id=${template})"
  else
    echo "--- destroying clone"
    tf destroy -auto-approve -input=false -no-color -var "template_vm_id=${template}" "${extra[@]}" >/dev/null
  fi
}
trap cleanup EXIT

start=$(date +%s)
echo "--- cloning template ${template}"
tf init -input=false -no-color >/dev/null
tf apply -auto-approve -input=false -no-color -var "template_vm_id=${template}" "${extra[@]}" | tail -3

echo "--- waiting for WinRM HTTPS on ${TEST_IP}:5986 (sysprep specialize + OOBE + cloudbase-init)"
deadline=$(( $(date +%s) + 1200 ))
until timeout 3 bash -c "</dev/tcp/${TEST_IP}/5986" 2>/dev/null; do
  (( $(date +%s) < deadline )) || { echo "FAIL: 5986 not reachable after 20 min"; exit 1; }
  sleep 10
done
echo "    reachable after $(( $(date +%s) - start ))s"

echo "--- checks over WinRM (NTLM, HTTPS)"
ADMIN_PASSWORD="$(jq -er .admin_password "${SECRETS_FILE}")" TEST_IP="${TEST_IP}" EXPECTED_HOST="${EXPECTED_HOST}" \
"${PY}" - <<'PY'
import os, sys, socket, winrm

s = winrm.Session(f"https://{os.environ['TEST_IP']}:5986/wsman",
                  auth=("Administrator", os.environ["ADMIN_PASSWORD"]),
                  transport="ntlm", server_cert_validation="ignore")
ps = r"""
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }).IPAddress -join ','
$svc = Get-Item WSMan:\localhost\Service\AllowUnencrypted, WSMan:\localhost\Service\Auth\Basic
"{0}|{1}|{2}|{3}|{4}" -f $env:COMPUTERNAME, $ip, $svc[0].Value, $svc[1].Value,
  (Get-CimInstance Win32_OperatingSystem).Caption  # ProductName still says "Windows 10" on Windows 11
"""
r = s.run_ps(ps)
if r.status_code != 0:
    sys.exit("FAIL: remote command error: " + r.std_err.decode(errors="replace"))
host, ip, unenc, basic, product = r.std_out.decode().strip().split("|")

http_open = True
try:
    socket.create_connection((os.environ["TEST_IP"], 5985), timeout=3).close()
except OSError:
    http_open = False

checks = [
    ("hostname from cloud-init", host == os.environ["EXPECTED_HOST"], host),
    ("static IP from cloud-init", ip == os.environ["TEST_IP"], ip),
    ("WinRM AllowUnencrypted off", unenc == "false", unenc),
    ("WinRM Basic auth off", basic == "false", basic),
    ("WinRM HTTP 5985 closed", not http_open, "open" if http_open else "closed"),
]
print(f"    OS: {product}")
for name, ok, value in checks:
    print(f"    [{'PASS' if ok else 'FAIL'}] {name}: {value}")
sys.exit(0 if all(ok for _, ok, _ in checks) else 1)
PY
echo "--- smoke test passed for template ${template} in $(( $(date +%s) - start ))s"
