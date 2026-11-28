#!/usr/bin/env bash
# Create missing lab secrets in ~/.config/lab/secrets.json (chmod 600). Idempotent: existing
# values are never changed, so running it again is always safe. Called by scripts/ansible.sh.
#
#   wireguard.keys.<name>  {private, public}  one per WireGuard instance and per road-warrior peer
#   wireguard.psk.<name>   pre-shared key per site-to-site tunnel (post-quantum hardening)
#   ad_dsrm_password       Directory Services Restore Mode password of the domain controllers
set -euo pipefail

SECRETS_FILE="${SECRETS_FILE:-${HOME}/.config/lab/secrets.json}"
WG_KEYS=(hq-fw01-s2s br-fw01-s2s hq-fw01-ra admin01 rw-test)
WG_PSKS=(hq-br)

command -v wg >/dev/null || { echo "error: wg (wireguard-tools) is required" >&2; exit 1; }
[[ -f "${SECRETS_FILE}" ]] || { echo "error: ${SECRETS_FILE} missing (run scripts/packer.sh once)" >&2; exit 1; }

umask 077
tmp="$(mktemp "${SECRETS_FILE}.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT
cp "${SECRETS_FILE}" "${tmp}"

added=0
for name in "${WG_KEYS[@]}"; do
  if ! jq -e --arg n "${name}" '.wireguard.keys[$n].private' "${tmp}" >/dev/null; then
    priv="$(wg genkey)"
    pub="$(wg pubkey <<<"${priv}")"
    jq --arg n "${name}" --arg priv "${priv}" --arg pub "${pub}" \
      '.wireguard.keys[$n] = {private: $priv, public: $pub}' "${tmp}" >"${tmp}.new" && mv "${tmp}.new" "${tmp}"
    added=$((added + 1))
  fi
done
for name in "${WG_PSKS[@]}"; do
  if ! jq -e --arg n "${name}" '.wireguard.psk[$n]' "${tmp}" >/dev/null; then
    jq --arg n "${name}" --arg psk "$(wg genpsk)" '.wireguard.psk[$n] = $psk' "${tmp}" >"${tmp}.new" && mv "${tmp}.new" "${tmp}"
    added=$((added + 1))
  fi
done

# Passwords: 24 chars, all four classes, alphabet free of XML/shell-special characters.
gen_password() {
  python3 -c '
import secrets, string
a = string.ascii_letters + string.digits + "-_.@#"
while True:
    p = "".join(secrets.choice(a) for _ in range(24))
    if any(c.islower() for c in p) and any(c.isupper() for c in p) and any(c.isdigit() for c in p) and any(c in "-_.@#" for c in p):
        print(p); break'
}
PASSWORDS=(ad_dsrm_password)
for name in "${PASSWORDS[@]}"; do
  if ! jq -e --arg n "${name}" '.[$n]' "${tmp}" >/dev/null; then
    jq --arg n "${name}" --arg pw "$(gen_password)" '.[$n] = $pw' "${tmp}" >"${tmp}.new" && mv "${tmp}.new" "${tmp}"
    added=$((added + 1))
  fi
done

if (( added > 0 )); then
  mv "${tmp}" "${SECRETS_FILE}"
  echo "lab-secrets: generated ${added} secret(s) in ${SECRETS_FILE}" >&2
fi
