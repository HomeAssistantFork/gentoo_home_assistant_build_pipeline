#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage7
require_root

log "Configuring bootloader and service ordering"
run_in_chroot "
set -euo pipefail
source /etc/profile

emerge --ask=n --noreplace sys-boot/grub
if [[ -d /sys/firmware/efi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot || true
else
  grub-install /dev/sda || true
fi

grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable docker
systemctl enable ha-os-release-sync.service
"

stage_end stage7
