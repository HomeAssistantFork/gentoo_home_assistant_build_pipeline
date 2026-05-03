#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage10
require_root

ISO_LABEL="${ISO_LABEL:-GENTOOHA}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/var/lib/ha-gentoo-hybrid/artifacts}"
WORK_DIR="${WORK_DIR:-/tmp/ha-stage10-$$}"
ARTIFACT_NAME="gentooha-${PLATFORM}-${FLAVOR}.${ARTIFACT_EXT}"

mkdir -p "$ARTIFACT_DIR" "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

KERNEL_IMAGE="$(ls -1 "$TARGET_ROOT"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$KERNEL_IMAGE" ]] || die "No kernel image found in $TARGET_ROOT/boot"
KERNEL_BASENAME="$(basename "$KERNEL_IMAGE")"
KERNEL_VERSION="${KERNEL_BASENAME#vmlinuz-}"
INITRAMFS_IMAGE="$TARGET_ROOT/boot/initramfs-${KERNEL_VERSION}.img"

log "Ensuring chroot has dracut for initramfs generation"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u
emerge --ask=n --noreplace sys-kernel/dracut
"

if [[ ! -f "$INITRAMFS_IMAGE" ]]; then
  log "Generating initramfs for ${KERNEL_VERSION}"
  run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u
dracut --force --kver '${KERNEL_VERSION}' --add dmsquash-live '/boot/initramfs-${KERNEL_VERSION}.img'
"
fi
[[ -f "$INITRAMFS_IMAGE" ]] || die "Initramfs not found: $INITRAMFS_IMAGE"

if [[ "$ARTIFACT_EXT" == "iso" ]]; then
  # ── x64 ISO path ────────────────────────────────────────────────────────────
  log "Preparing host tools for ISO generation"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -q >/dev/null
    apt-get install -y -q xorriso grub-pc-bin grub-efi-amd64-bin mtools squashfs-tools rsync >/dev/null
  else
    die "apt-get not found; install xorriso, grub-mkrescue, mksquashfs manually"
  fi
  command -v grub-mkrescue >/dev/null 2>&1 || die "grub-mkrescue not found"
  command -v mksquashfs    >/dev/null 2>&1 || die "mksquashfs not found"

  ISO_ROOT="$WORK_DIR/iso"
  mkdir -p "$ISO_ROOT/boot/grub" "$ISO_ROOT/LiveOS"

  log "Building compressed live rootfs squashfs"
  mksquashfs "$TARGET_ROOT" "$ISO_ROOT/LiveOS/rootfs.squashfs" \
    -wildcards \
    -e proc sys dev run tmp var/tmp var/cache/distfiles

  log "Copying kernel and initramfs into ISO tree"
  cp "$KERNEL_IMAGE"    "$ISO_ROOT/boot/vmlinuz"
  cp "$INITRAMFS_IMAGE" "$ISO_ROOT/boot/initramfs.img"

  if [[ "$FLAVOR" == "installer" ]]; then
    # Write an install script into the live system
    cp -a "$TARGET_ROOT/root" "$ISO_ROOT/root" 2>/dev/null || true
    cat > "$ISO_ROOT/root/install.sh" <<'INSTALL'
#!/bin/bash
# GentooHA installer — run from live environment
set -euo pipefail
echo "GentooHA Installer"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop
read -rp "Target disk (e.g. sda): " DISK
[[ -b "/dev/$DISK" ]] || { echo "Not a block device: /dev/$DISK"; exit 1; }
read -rp "WARNING: /dev/$DISK will be wiped. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1
dd if=/proc/self/fd/0 of=/dev/$DISK bs=4M status=progress conv=fsync < /dev/zero &>/dev/null || true
cp /run/rootfsbase/LiveOS/rootfs.squashfs /tmp/rootfs.squashfs
unsquashfs -d /mnt/install /tmp/rootfs.squashfs
grub-install --target=x86_64-efi --efi-directory=/mnt/install/boot/efi --bootloader-id=GentooHA /dev/$DISK || true
grub-install --target=i386-pc /dev/$DISK || true
echo "Installation complete. Reboot without the ISO."
INSTALL
    chmod +x "$ISO_ROOT/root/install.sh"
  fi

  cat > "$ISO_ROOT/boot/grub/grub.cfg" <<GRUBCFG
set default=0
set timeout=5

menuentry "GentooHA Live (systemd + HA Supervisor)" {
  linux /boot/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image rw console=tty0
  initrd /boot/initramfs.img
}
GRUBCFG

  if [[ "$FLAVOR" == "installer" ]]; then
    cat >> "$ISO_ROOT/boot/grub/grub.cfg" <<GRUBINS

menuentry "GentooHA Install to disk" {
  linux /boot/vmlinuz root=live:CDLABEL=${ISO_LABEL} rd.live.image rw console=tty0 gentooha.install=1
  initrd /boot/initramfs.img
}
GRUBINS
  fi

  OUT_ARTIFACT="$ARTIFACT_DIR/$ARTIFACT_NAME"
  log "Creating ISO: $OUT_ARTIFACT"
  grub-mkrescue -o "$OUT_ARTIFACT" "$ISO_ROOT" -- -V "$ISO_LABEL" >/dev/null
  [[ -f "$OUT_ARTIFACT" ]] || die "ISO was not created"
  log "ISO created: $OUT_ARTIFACT ($(du -sh "$OUT_ARTIFACT" | cut -f1))"

else
  # ── ARM IMG path ─────────────────────────────────────────────────────────────
  log "Preparing host tools for IMG generation"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -q >/dev/null
    apt-get install -y -q dosfstools parted kpartx rsync squashfs-tools >/dev/null
  else
    die "apt-get not found; install dosfstools, parted, kpartx, rsync manually"
  fi

  IMG_SIZE_MB="${IMG_SIZE_MB:-3072}"
  BOOT_SIZE_MB="${BOOT_SIZE_MB:-256}"
  IMG_FILE="$WORK_DIR/${ARTIFACT_NAME%.img}.raw"

  log "Creating ${IMG_SIZE_MB}MB raw image: $IMG_FILE"
  dd if=/dev/zero of="$IMG_FILE" bs=1M count="$IMG_SIZE_MB" status=progress

  log "Partitioning: ${BOOT_SIZE_MB}MB FAT32 boot + rest ext4 root"
  parted -s "$IMG_FILE" \
    mklabel msdos \
    mkpart primary fat32 1MiB "${BOOT_SIZE_MB}MiB" \
    set 1 boot on \
    mkpart primary ext4 "${BOOT_SIZE_MB}MiB" 100%

  LOOP_DEV="$(losetup -fP --show "$IMG_FILE")"
  trap 'losetup -d "$LOOP_DEV" 2>/dev/null; rm -rf "$WORK_DIR"' EXIT

  log "Formatting partitions on $LOOP_DEV"
  mkfs.vfat -F 32 -n BOOT "${LOOP_DEV}p1"
  mkfs.ext4 -L ROOT "${LOOP_DEV}p2"

  MOUNT_BOOT="$WORK_DIR/mnt/boot"
  MOUNT_ROOT="$WORK_DIR/mnt/root"
  mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"

  mount "${LOOP_DEV}p2" "$MOUNT_ROOT"
  mkdir -p "$MOUNT_ROOT/boot"
  mount "${LOOP_DEV}p1" "$MOUNT_BOOT"

  log "Copying rootfs to image (excluding virtual filesystems)"
  rsync -aHAX --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
    --exclude=/tmp --exclude=/var/tmp --exclude=/var/cache/distfiles \
    "$TARGET_ROOT/" "$MOUNT_ROOT/"

  log "Copying kernel, initramfs, and DTBs to boot partition"
  cp "$KERNEL_IMAGE"    "$MOUNT_BOOT/vmlinuz"
  cp "$INITRAMFS_IMAGE" "$MOUNT_BOOT/initramfs.img"
  find "$TARGET_ROOT/boot" -name '*.dtb' -exec cp {} "$MOUNT_BOOT/" \; 2>/dev/null || true

  # Platform-specific bootloader config
  case "$PLATFORM" in
    pi3|pi4|pizero2)
      cat > "$MOUNT_BOOT/cmdline.txt" <<CMDLINE
root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait console=serial0,115200 console=tty1 loglevel=3
CMDLINE
      cat > "$MOUNT_BOOT/config.txt" <<PICONFIG
arm_64bit=1
kernel=vmlinuz
initramfs initramfs.img followkernel
dtoverlay=miniuart-bt
PICONFIG
      ;;
    bbb)
      cat > "$MOUNT_BOOT/uEnv.txt" <<UENV
uname_r=${KERNEL_VERSION}
cmdline=root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait
UENV
      ;;
    pbv2)
      cat > "$MOUNT_BOOT/uEnv.txt" <<UENV
# PocketBeagle v2 / AM62x boot environment
uname_r=${KERNEL_VERSION}
cmdline=root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait
# TODO: PowerVR SGX GPU firmware blob and pvrsrvkm module not yet included
UENV
      ;;
  esac

  if [[ "$FLAVOR" == "installer" ]]; then
    cat > "$MOUNT_ROOT/root/install.sh" <<'INSTALL'
#!/bin/bash
# GentooHA ARM installer — run from live system
set -euo pipefail
echo "GentooHA ARM Installer"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop
read -rp "Target disk (e.g. mmcblk1): " DISK
[[ -b "/dev/$DISK" ]] || { echo "Not a block device: /dev/$DISK"; exit 1; }
read -rp "WARNING: /dev/$DISK will be wiped. Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1
dd if=/proc/self/fd/0 of=/dev/$DISK bs=4M status=progress conv=fsync < /dev/zero &>/dev/null || true
cp /run/rootfsbase/gentooha.img /tmp/gentooha.img
dd if=/tmp/gentooha.img of=/dev/$DISK bs=4M status=progress conv=fsync
echo "Installation complete. Remove media and reboot."
INSTALL
    chmod +x "$MOUNT_ROOT/root/install.sh"
    # Auto-run install on first real boot via a systemd oneshot
    cat > "$MOUNT_ROOT/etc/systemd/system/gentooha-install.service" <<SVC
[Unit]
Description=GentooHA First-Boot Installer
ConditionPathExists=/root/.run-install
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/root/install.sh
ExecStartPost=/bin/rm -f /root/.run-install
StandardInput=tty
TTYPath=/dev/tty1

[Install]
WantedBy=multi-user.target
SVC
    touch "$MOUNT_ROOT/root/.run-install"
    ln -sf /etc/systemd/system/gentooha-install.service \
       "$MOUNT_ROOT/etc/systemd/system/multi-user.target.wants/gentooha-install.service" 2>/dev/null || true
  fi

  log "Unmounting image"
  umount "$MOUNT_BOOT" "$MOUNT_ROOT"
  losetup -d "$LOOP_DEV"
  trap 'rm -rf "$WORK_DIR"' EXIT  # reset trap after losetup detach

  OUT_ARTIFACT="$ARTIFACT_DIR/$ARTIFACT_NAME"
  log "Compressing image: $OUT_ARTIFACT.xz"
  xz -T0 -c "$IMG_FILE" > "${OUT_ARTIFACT}.xz"
  # Also keep uncompressed for direct dd use
  mv "$IMG_FILE" "$OUT_ARTIFACT"

  log "IMG created: $OUT_ARTIFACT ($(du -sh "$OUT_ARTIFACT" | cut -f1))"
fi

stage_end stage10
