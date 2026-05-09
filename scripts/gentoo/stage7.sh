#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage7
require_root
mount_chroot_fs

log "Configuring bootloader and service ordering"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u

emerge --ask=n --noreplace sys-boot/grub

if command -v grub-install >/dev/null 2>&1; then
  if [[ -d /sys/firmware/efi ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot || echo 'WARN: grub-install EFI failed; continuing with image build'
  else
    grub-install /dev/sda || echo 'WARN: grub-install BIOS failed; continuing with image build'
  fi
else
  echo 'WARN: grub-install not available in chroot; continuing with image build'
fi

if command -v grub-mkconfig >/dev/null 2>&1; then
  grub-mkconfig -o /boot/grub/grub.cfg || echo 'WARN: grub-mkconfig failed; continuing with image build'
else
  echo 'WARN: grub-mkconfig not available in chroot; continuing with image build'
fi

systemctl enable docker
systemctl enable ha-os-release-sync.service
"

stage_end stage7
