#!/bin/sh
# Golden-image content: current packages and the QEMU guest agent (Proxmox shows IPs, runs
# freeze/thaw for backups, and automation can exec through it without network access).
set -eu
export DEBIAN_FRONTEND=noninteractive

# The base image's first boot is still running cloud-init (apt sources, SSH host keys).
cloud-init status --wait >/dev/null || true

apt-get update
apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
apt-get -y install qemu-guest-agent
systemctl start qemu-guest-agent # static unit, started by udev on boot when the virtio port exists
systemctl is-active qemu-guest-agent
