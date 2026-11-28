#!/usr/bin/env bash
# Run Terraform for the lab environment with the Proxmox API token loaded from a
# user-only file, so the secret never lands in code, shell history or tfvars.
#
# Usage: scripts/tf.sh <terraform args...>     e.g. scripts/tf.sh plan -out=tfplan
#   TOKEN_FILE  override token location (default ~/.config/pve/terraform-token.json)
#   TF_ENV      environment dir under terraform/envs (default lab)
set -euo pipefail

TOKEN_FILE="${TOKEN_FILE:-${HOME}/.config/pve/terraform-token.json}"
TF_ENV="${TF_ENV:-lab}"
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

[[ -r "${TOKEN_FILE}" ]] || { echo "error: token file ${TOKEN_FILE} not readable" >&2; exit 1; }
if [[ "$(stat -c %a "${TOKEN_FILE}")" != "600" ]]; then
  echo "error: ${TOKEN_FILE} must be chmod 600" >&2
  exit 1
fi

# pveum JSON: {"full-tokenid": "user@realm!name", "value": "<uuid>"}
PROXMOX_VE_API_TOKEN="$(jq -er '."full-tokenid" + "=" + .value' "${TOKEN_FILE}")"
export PROXMOX_VE_API_TOKEN

# Lab automation public key for cloud-init users (not a secret, but lives outside the repo).
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-${HOME}/.config/lab/id_ed25519.pub}"
if [[ -r "${SSH_PUBKEY_FILE}" ]]; then
  TF_VAR_lab_ssh_public_key="$(cat "${SSH_PUBKEY_FILE}")"
  export TF_VAR_lab_ssh_public_key
fi

exec terraform -chdir="${ROOT}/terraform/envs/${TF_ENV}" "$@"
