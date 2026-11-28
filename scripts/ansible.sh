#!/usr/bin/env bash
# Run ansible-playbook with the repo's config, from the ansible/ directory.
#
# Usage: scripts/ansible.sh <playbook> [ansible-playbook args]   e.g. scripts/ansible.sh playbooks/firewalls.yml --check
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "${ROOT}/ansible"
export ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg"
exec ansible-playbook "$@"
