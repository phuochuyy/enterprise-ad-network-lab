#!/usr/bin/env bash
# Build a template with Packer, credentials loaded from user-only files.
#
# Usage: scripts/packer.sh <ws2022-core|ws2022-desktop|win11|opnsense> [init|validate|build] [extra packer args]
#
#   Proxmox token : ~/.config/pve/terraform-token.json (same token as Terraform)
#   Lab secrets   : ~/.config/lab/secrets.json  {"admin_password": "...", "opnsense_root_password": "..."}
#                   admin_password is generated on first use
#   SSH key       : ~/.config/lab/id_ed25519 (lab automation key; OPNsense root login)
set -euo pipefail

TOKEN_FILE="${TOKEN_FILE:-${HOME}/.config/pve/terraform-token.json}"
SECRETS_FILE="${SECRETS_FILE:-${HOME}/.config/lab/secrets.json}"
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SSH_KEY="${SSH_KEY:-${HOME}/.config/lab/id_ed25519}"

die() { echo "error: $*" >&2; exit 1; }

target="${1:-}"; action="${2:-build}"
# Windows templates share one source, parameterised by vars/<target>.pkrvars.hcl; other targets
# are a directory of their own under packer/.
if [[ -n "${target}" && -f "${ROOT}/packer/windows/vars/${target}.pkrvars.hcl" ]]; then
  PKR_DIR="${ROOT}/packer/windows"
  var_args=(-var-file="vars/${target}.pkrvars.hcl")
elif [[ "${target}" == "opnsense" ]]; then
  PKR_DIR="${ROOT}/packer/opnsense"
  var_args=()
else
  die "usage: $(basename "$0") <$(find "${ROOT}/packer/windows/vars" -name '*.pkrvars.hcl' -printf '%f\n' | sed 's/.pkrvars.hcl//' | sort | paste -sd'|')|opnsense> [init|validate|build]"
fi
shift $(( $# >= 2 ? 2 : 1 ))

check_mode() { [[ "$(stat -c %a "$1")" == "600" ]] || die "$1 must be chmod 600"; }

# Generate a strong admin password once. Alphabet avoids XML/shell-special characters
# because it is embedded in unattend XML; length compensates for the smaller alphabet.
if [[ ! -f "${SECRETS_FILE}" ]]; then
  mkdir -p "$(dirname "${SECRETS_FILE}")"
  (umask 077 && python3 -c '
import json, secrets, string
alphabet = string.ascii_letters + string.digits + "-_.@#"
while True:
    pw = "".join(secrets.choice(alphabet) for _ in range(24))
    if any(c.islower() for c in pw) and any(c.isupper() for c in pw) and any(c.isdigit() for c in pw) and any(c in "-_.@#" for c in pw):
        break
print(json.dumps({"admin_password": pw}))' > "${SECRETS_FILE}")
  echo "generated lab admin password in ${SECRETS_FILE}" >&2
fi
check_mode "${TOKEN_FILE}"
check_mode "${SECRETS_FILE}"

PROXMOX_URL="https://127.0.0.1:8006/api2/json"
PROXMOX_USERNAME="$(jq -er '."full-tokenid"' "${TOKEN_FILE}")"
PROXMOX_TOKEN="$(jq -er '.value' "${TOKEN_FILE}")"
PKR_VAR_admin_password="$(jq -er '.admin_password' "${SECRETS_FILE}")"
export PROXMOX_URL PROXMOX_USERNAME PROXMOX_TOKEN PKR_VAR_admin_password

if [[ "${target}" == "opnsense" ]]; then
  check_mode "${SSH_KEY}"
  # OPNsense verifies with PHP password_verify(), which accepts crypt(3) SHA-512 hashes.
  PKR_VAR_root_password_hash="$(jq -er '.opnsense_root_password' "${SECRETS_FILE}" | openssl passwd -6 -stdin)"
  PKR_VAR_ssh_public_key="$(cat "${SSH_KEY}.pub")"
  PKR_VAR_ssh_private_key_file="${SSH_KEY}"
  export PKR_VAR_root_password_hash PKR_VAR_ssh_public_key PKR_VAR_ssh_private_key_file
fi

cd "${PKR_DIR}"
case "${action}" in
  init) exec packer init . ;;
  validate) exec packer validate "${var_args[@]}" "$@" . ;;
  build)
    mkdir -p logs
    PACKER_LOG_PATH="logs/${target}-$(date +%Y%m%d-%H%M%S).log"
    export PACKER_LOG=1 PACKER_LOG_PATH
    exec packer build -force -on-error=abort "${var_args[@]}" "$@" .
    ;;
  *) die "unknown action: ${action}" ;;
esac
