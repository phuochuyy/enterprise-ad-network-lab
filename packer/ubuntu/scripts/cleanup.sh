#!/bin/sh
# Reset everything that must be unique per clone, so cloud-init treats every clone as a new
# instance: machine-id, SSH host keys, cloud-init state and logs, netplan from the build.
set -eu
export DEBIAN_FRONTEND=noninteractive

apt-get -y autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/*

cloud-init clean --logs --machine-id --seed
rm -f /etc/ssh/ssh_host_*
rm -f /etc/netplan/50-cloud-init.yaml
find /var/log -type f -name '*.log' -exec truncate -s 0 {} +
rm -f /home/*/.bash_history /root/.bash_history
sync
