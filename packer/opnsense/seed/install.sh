#!/bin/sh
# Unattended OPNsense install, run from the live DVD shell by Packer's boot_command:
#   mkdir /tmp/seed && mount_cd9660 /dev/iso9660/OPNSEED /tmp/seed && sh /tmp/seed/install.sh
#
# Replays the stock "Install (UFS)" path of /usr/libexec/bsdinstall/opnsense (opnsense-ufs,
# mount, opnsense-install, bootconfig) without its bsddialog prompts, then drops in the seed
# config.xml so the installed system boots with SSH and a static WAN address for Packer.
#
# No console is watched during the build, so the log is also pushed to the host
# (nc to ${LOG_HOST}:${LOG_PORT}) when the script exits, successfully or not.
set -eu

SEED=/tmp/seed
LOG=/tmp/install.log
LOG_HOST=10.10.10.1
LOG_PORT=8999
LIVE_IP=10.10.10.249/24 # live system only; the installed system uses the build IP from config.xml

push_log() {
    rc=$?
    echo "install.sh exit code ${rc}" >>"${LOG}"
    nc -N -w 5 "${LOG_HOST}" "${LOG_PORT}" <"${LOG}" || true
    if [ "${rc}" -eq 0 ]; then
        reboot
    fi
}
trap push_log EXIT

: >"${LOG}"
step() { echo "=== $*" | tee -a "${LOG}"; }

# The live system assigns LAN=vtnet0, WAN=vtnet1 automatically; vtnet1 sits on the build bridge.
ifconfig vtnet1 inet "${LIVE_IP}" up 2>>"${LOG}" || true

DISK="$(sysctl -n kern.disks | tr ' ' '\n' | grep -E '^(da|vtbd|ada|nda)[0-9]+$' | head -1)"
[ -n "${DISK}" ] || { step "no target disk found"; exit 1; }
step "target disk ${DISK}"

export BSDINSTALL_CHROOT=/mnt
export BSDINSTALL_TMPETC=/tmp/bsdinstall_etc
export WORKAROUND_HYBRID=1
mkdir -p "${BSDINSTALL_TMPETC}"

step "partition (EFI 260M, BIOS boot 512K, UFS root, no swap)"
{
    gpart destroy -F "${DISK}" || true
    # Braces are bsdinstall's own partition-list syntax, passed literally.
    bsdinstall scriptedpart "${DISK}" gpt '{' 260M efi, 512K freebsd-boot, auto freebsd-ufs / '}'
    gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 2 "${DISK}"
    gpart modify -i 1 -l efifs "${DISK}"
    gpart modify -i 2 -l bootfs "${DISK}"
    gpart modify -i 3 -l rootfs "${DISK}"
} >>"${LOG}" 2>&1
sed -e "s:/${DISK}p3:/gpt/rootfs:" -e "s:/${DISK}p1:/gpt/efifs:" \
    "${BSDINSTALL_TMPETC}/fstab" >"${BSDINSTALL_TMPETC}/fstab.new"
mv "${BSDINSTALL_TMPETC}/fstab.new" "${BSDINSTALL_TMPETC}/fstab"
cat "${BSDINSTALL_TMPETC}/fstab" >>"${LOG}"

step "mount"
bsdinstall mount >>"${LOG}" 2>&1

# opnsense-install draws a bsddialog gauge on the console (stdout); keep stdout on the tty.
step "copy live system to disk (opnsense-install)"
bsdinstall opnsense-install 2>>"${LOG}"
cat /mnt/var/log/installer.log >>"${LOG}" 2>/dev/null || true

step "boot loader"
bsdinstall bootconfig >>"${LOG}" 2>&1

step "seed config.xml"
cp "${SEED}/config.xml" /mnt/conf/config.xml
chmod 0644 /mnt/conf/config.xml

step "unmount"
umount /mnt/dev 2>>"${LOG}" || true
bsdinstall umount >>"${LOG}" 2>&1
sync
step "done - rebooting into the installed system"
