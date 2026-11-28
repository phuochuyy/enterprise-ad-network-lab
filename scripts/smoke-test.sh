#!/usr/bin/env bash
# Template acceptance test: clone -> boot -> verify from the outside -> destroy.
#
# Usage: scripts/smoke-test.sh <template_vm_id> [win11|linux]
#   KEEP=1  leave the clone running for inspection
#
# Windows (default, win11 adds TPM + 64 GB): passes when the clone comes up with the cloud-init
# hostname and static IP, WinRM answers over HTTPS (5986) with NTLM, Basic/unencrypted are off
# and plain HTTP (5985) is closed - exactly how Ansible will reach real VMs.
# linux: passes when the clone takes hostname, static IP and SSH key from cloud-init, cloud-init
# finished cleanly, and the QEMU guest agent runs and answers the Proxmox API.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SECRETS_FILE="${SECRETS_FILE:-${HOME}/.config/lab/secrets.json}"
PY="${HOME}/.local/share/pipx/venvs/ansible-core/bin/python" # has pywinrm
SSH_KEY="${SSH_KEY:-${HOME}/.config/lab/id_ed25519}"
TOKEN_FILE="${TOKEN_FILE:-${HOME}/.config/pve/terraform-token.json}"
TEST_IP="10.10.10.60"
EXPECTED_HOST="HQ-TST01"

template="${1:?usage: smoke-test.sh <template_vm_id> [win11|linux]}"
mode="${2:-windows}"
extra=()
case "${mode}" in
  windows) ;;
  win11) extra=(-var tpm=true -var disk_gb=64) ;;
  linux)
    extra=(-var os_type=l26 -var bios=seabios -var memory_mb=1024 -var disk_gb=8
      -var ci_type=nocloud -var ci_username=ansible
      -var "ci_ssh_keys=[\"$(cat "${SSH_KEY}.pub")\"]")
    ;;
  *) echo "unknown mode: ${mode}" >&2; exit 2 ;;
esac

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

port=5986; [[ "${mode}" == "linux" ]] && port=22
echo "--- waiting for ${TEST_IP}:${port} (first boot + cloud-init)"
deadline=$(( $(date +%s) + 1200 ))
until timeout 3 bash -c "</dev/tcp/${TEST_IP}/${port}" 2>/dev/null; do
  (( $(date +%s) < deadline )) || { echo "FAIL: ${port} not reachable after 20 min"; exit 1; }
  sleep 10
done
echo "    reachable after $(( $(date +%s) - start ))s"

if [[ "${mode}" == "linux" ]]; then
  echo "--- checks over SSH (cloud-init key) and the Proxmox guest-agent API"
  # Throwaway clone with a fresh host key on every run: do not record it anywhere.
  ssh_cmd=(ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o BatchMode=yes -o LogLevel=ERROR "ansible@${TEST_IP}")
  # shellcheck disable=SC2016 # expanded on the guest
  IFS="|" read -r host ip agent ci os < <("${ssh_cmd[@]}" 'cloud-init status --wait >/dev/null 2>&1
    printf "%s|%s|%s|%s|%s\n" "$(hostname)" \
      "$(ip -4 -o addr show scope global | awk "{print \$4}" | cut -d/ -f1 | paste -sd,)" \
      "$(systemctl is-active qemu-guest-agent)" "$(cloud-init status | awk "{print \$2}")" \
      "$(. /etc/os-release && echo "${PRETTY_NAME}")"')
  token="$(jq -er '."full-tokenid" + "=" + .value' "${TOKEN_FILE}")"
  vmid="$(TF_ENV=template-smoke "${ROOT}/scripts/tf.sh" output -raw vm_id)"
  ping="$(curl -sk -H "Authorization: PVEAPIToken=${token}" -X POST \
    "https://127.0.0.1:8006/api2/json/nodes/pve/qemu/${vmid}/agent/ping" | jq -r 'if .data then "answers" else (.message // "no answer") end')"
  echo "    OS: ${os}"
  fail=0
  check() { if [[ "$2" == "$3" ]]; then echo "    [PASS] $1: $2"; else echo "    [FAIL] $1: $2 (want $3)"; fail=1; fi; }
  check "hostname from cloud-init" "${host^^}" "${EXPECTED_HOST}"
  check "static IP from cloud-init" "${ip}" "${TEST_IP}"
  check "cloud-init finished" "${ci}" "done"
  check "qemu-guest-agent service" "${agent}" "active"
  check "guest agent answers Proxmox" "${ping}" "answers"
  (( fail == 0 )) || exit 1
  echo "--- smoke test passed for template ${template} in $(( $(date +%s) - start ))s"
  exit 0
fi

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
