#!/bin/bash
set -euo pipefail

IMG=/var/lib/ha-gentoo-hybrid/artifacts/gentooha-x64-debug.img
MNT=/tmp/vdi_inspect

mkdir -p "$MNT"

if [ ! -f "$IMG" ]; then
  echo "No raw img found"
  ls /var/lib/ha-gentoo-hybrid/artifacts/
  exit 1
fi

echo "Image: $IMG ($(du -sh "$IMG" | cut -f1))"
fdisk -l "$IMG" 2>/dev/null || true

# Get sector size and start of first partition
SECTORSIZE=$(fdisk -l "$IMG" 2>/dev/null | grep "Sector size" | awk '{print $4}')
SECTORSIZE=${SECTORSIZE:-512}
PARTSTART=$(fdisk -l "$IMG" 2>/dev/null | awk '/^[^ ]*1/{print $2}')
PARTSTART=${PARTSTART:-2048}
BYTEOFF=$((PARTSTART * SECTORSIZE))
echo "Mounting partition at offset $BYTEOFF (sector $PARTSTART * $SECTORSIZE)"

mount -o loop,ro,offset=$BYTEOFF "$IMG" "$MNT" 2>&1 || { echo "mount failed"; exit 1; }

echo "=== Boot files ==="
ls "$MNT/" 2>/dev/null
ls "$MNT/syslinux/" 2>/dev/null || true
ls "$MNT/extlinux/" 2>/dev/null || true
ls "$MNT/boot/" 2>/dev/null || true

echo "=== syslinux config ==="
cat "$MNT/syslinux/syslinux.cfg" 2>/dev/null || true
cat "$MNT/extlinux/extlinux.conf" 2>/dev/null || true
cat "$MNT/boot/extlinux/extlinux.conf" 2>/dev/null || true

umount "$MNT"
echo "Done"
