#!/usr/bin/env bash
# Pull Windows Setup / sysprep / cloudbase-init logs straight off a STOPPED VM's disk, for a
# clone that never comes up on the network (no WinRM, no guest agent, no console at hand).
# Strictly read-only: the disk is attached as a read-only loop device and read with ntfscat,
# nothing is mounted or written to it.
#
# Usage: sudo scripts/diag/win-offline-logs.sh <vmid> [out_dir]
#   out_dir defaults to ./diag-<vmid>-<timestamp>; files are handed back to $SUDO_USER.
set -euo pipefail

vmid="${1:?usage: sudo $0 <vmid> [out_dir]}"
out="${2:-diag-${vmid}-$(date +%Y%m%d-%H%M%S)}"
die() { echo "error: $*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "needs root (raw disk access): sudo $0 $*"
command -v ntfscat >/dev/null || die "ntfscat missing (apt install ntfs-3g)"
qm status "${vmid}" | grep -q 'status: stopped' || die "VM ${vmid} must be stopped first"

# Boot disk (scsi0) -> block device, e.g. local-lvm:vm-999-disk-1 -> /dev/pve/vm-999-disk-1
volid="$(qm config "${vmid}" | awk -F'[ ,]' '/^scsi0:/ {print $2}')"
[[ -n "${volid}" ]] || die "VM ${vmid} has no scsi0 disk"
dev="$(pvesm path "${volid}")"

loop="$(losetup --read-only --partscan --find --show "${dev}")"
trap 'losetup -d "${loop}"' EXIT
udevadm settle
# The Windows volume is the largest NTFS partition (the others are EFI, MSR and recovery).
part="$(lsblk -nrbpo NAME,FSTYPE,SIZE "${loop}" | awk '$2=="ntfs"' | sort -k3 -n | tail -1 | cut -d' ' -f1)"
[[ -n "${part}" ]] || die "no NTFS partition found on ${dev}"

mkdir -p "${out}"
cbi='Program Files/Cloudbase Solutions/Cloudbase-Init/log'
for f in \
  'Windows/Panther/setupact.log' 'Windows/Panther/setuperr.log' \
  'Windows/Panther/UnattendGC/setupact.log' 'Windows/Panther/UnattendGC/setuperr.log' \
  'Windows/System32/Sysprep/Panther/setupact.log' 'Windows/System32/Sysprep/Panther/setuperr.log' \
  'Windows/Setup/State/State.ini' 'Windows/Panther/reset-build-network.log' \
  "${cbi}/cloudbase-init-unattend.log" "${cbi}/cloudbase-init.log"; do
  # Answer files are skipped on purpose: they hold the Administrator password in plain text.
  dst="${out}/$(tr '/ ' '__' <<<"${f}")"
  if ntfscat -f "${part}" "${f}" >"${dst}" 2>/dev/null; then
    echo "ok       ${f}"
  else
    rm -f "${dst}"
    echo "missing  ${f}"
  fi
done

[[ -n "${SUDO_USER:-}" ]] && chown -R "${SUDO_USER}:" "${out}"
echo "logs in ${out}"
