#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage11
require_root
mount_chroot_fs

ARTIFACT_DIR="${ARTIFACT_DIR:-/var/lib/ha-gentoo-hybrid/artifacts}"
WORK_DIR="${WORK_DIR:-/var/lib/ha-gentoo-hybrid/work/stage11-$$}"
ARTIFACT_NAME="gentooha-${PLATFORM}-${FLAVOR}.${ARTIFACT_EXT}"

BASE_BOOT_ARGS="rw systemd.show_status=1"
if [[ "$FLAVOR" == "debug" ]]; then
  DEBUG_BOOT_ARGS="rd.debug rd.info rd.shell loglevel=7 ignore_loglevel systemd.log_level=debug systemd.log_target=console printk.devkmsg=on"
else
  DEBUG_BOOT_ARGS=""
fi

mkdir -p "$ARTIFACT_DIR" "$WORK_DIR"

cleanup() {
  set +e
  if [[ -n "${MOUNT_ROOT:-}" ]]; then
    for d in run sys proc dev; do
      if mountpoint -q "$MOUNT_ROOT/$d"; then
        umount -R "$MOUNT_ROOT/$d" || true
      fi
    done
  fi
  if [[ -n "${MOUNT_BOOT:-}" ]] && mountpoint -q "$MOUNT_BOOT"; then
    umount "$MOUNT_BOOT" || true
  fi
  if [[ -n "${MOUNT_ROOT:-}" ]] && mountpoint -q "$MOUNT_ROOT"; then
    umount "$MOUNT_ROOT" || true
  fi
  if [[ -n "${LOOP_DEV:-}" ]]; then
    losetup -d "$LOOP_DEV" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

KERNEL_IMAGE="$(ls -1 "$TARGET_ROOT"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -z "$KERNEL_IMAGE" ]]; then
  KERNEL_IMAGE="$(ls -1 "$TARGET_ROOT"/boot/kernel-* 2>/dev/null | sort -V | tail -n1 || true)"
fi
[[ -n "$KERNEL_IMAGE" ]] || die "No kernel image found in $TARGET_ROOT/boot"
KERNEL_BASENAME="$(basename "$KERNEL_IMAGE")"
if [[ "$KERNEL_BASENAME" == vmlinuz-* ]]; then
  KERNEL_VERSION="${KERNEL_BASENAME#vmlinuz-}"
else
  KERNEL_VERSION="${KERNEL_BASENAME#kernel-}"
fi
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
dracut --force --kver '${KERNEL_VERSION}' '/boot/initramfs-${KERNEL_VERSION}.img'
"
fi
[[ -f "$INITRAMFS_IMAGE" ]] || die "Initramfs not found: $INITRAMFS_IMAGE"

if [[ "$FLAVOR" == "debug" ]]; then
  log "Enabling persistent journald logs in target root for debug flavor"
  mkdir -p "$TARGET_ROOT/etc/systemd/journald.conf.d" "$TARGET_ROOT/var/log/journal"
  cat > "$TARGET_ROOT/etc/systemd/journald.conf.d/99-gentooha-debug.conf" <<'JOURNALCFG'
[Journal]
Storage=persistent
SystemMaxUse=200M
JOURNALCFG
fi

if [[ "$PLATFORM" == "x64" ]]; then
  log "Building preinstalled x64 disk image (raw + vdi) using syslinux/extlinux"

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -q >/dev/null
    apt-get install -y -q dosfstools parted rsync qemu-utils syslinux-common extlinux >/dev/null
  else
    die "apt-get not found; install dosfstools, parted, rsync, qemu-utils, syslinux-common, extlinux manually"
  fi

  # Find syslinux MBR binary
  MBR_BIN=""
  for candidate in \
    /usr/lib/syslinux/mbr/mbr.bin \
    /usr/lib/syslinux/mbr.bin \
    /usr/share/syslinux/mbr.bin \
    /usr/share/syslinux/mbr/mbr.bin; do
    [[ -f "$candidate" ]] && { MBR_BIN="$candidate"; break; }
  done
  [[ -n "$MBR_BIN" ]] || die "syslinux mbr.bin not found; ensure syslinux-common is installed"
  log "Using MBR: $MBR_BIN"

  IMG_SIZE_MB="${IMG_SIZE_MB:-12288}"
  RAW_FILE="$WORK_DIR/${ARTIFACT_NAME}"
  MOUNT_ROOT="$WORK_DIR/mnt/root"

  AVAIL_MB="$(df -Pm "$WORK_DIR" | awk 'NR==2 {print $4}')"
  NEED_MB="$((IMG_SIZE_MB + 1024))"
  (( AVAIL_MB >= NEED_MB )) || die "Insufficient space (${AVAIL_MB}MB free, need ${NEED_MB}MB)"

  log "Creating ${IMG_SIZE_MB}MB raw image"
  dd if=/dev/zero of="$RAW_FILE" bs=1M count="$IMG_SIZE_MB" status=progress

  log "Partitioning: MBR + single bootable ext4 partition starting at 1MiB"
  parted -s "$RAW_FILE" \
    mklabel msdos \
    mkpart primary ext4 1MiB 100% \
    set 1 boot on

  LOOP_DEV="$(losetup -fP --show "$RAW_FILE")"
  mkfs.ext4 -F -L gentooha "${LOOP_DEV}p1"

  mkdir -p "$MOUNT_ROOT"
  mount "${LOOP_DEV}p1" "$MOUNT_ROOT"

  log "Copying GentooHA rootfs into image"
  rsync -aHAX --delete \
    --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
    --exclude=/tmp --exclude=/var/tmp --exclude=/var/cache/distfiles \
    "$TARGET_ROOT/" "$MOUNT_ROOT/"

  ROOT_UUID="$(blkid -s UUID -o value "${LOOP_DEV}p1")"
  cat > "$MOUNT_ROOT/etc/fstab" <<FSTAB
UUID=${ROOT_UUID} / ext4 defaults 0 1
FSTAB

  if [[ "$FLAVOR" == "debug" ]]; then
    log "Enabling tty1 root autologin for debug flavor"
    mkdir -p "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d"
    cat > "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 115200,38400,9600 $TERM
AUTOLOGIN
    if [[ -f "$MOUNT_ROOT/etc/shadow" ]]; then
      sed -i 's#^root:[^:]*:#root::#' "$MOUNT_ROOT/etc/shadow" || true
    fi
  fi

  log "Installing extlinux bootloader into /boot"
  mkdir -p "$MOUNT_ROOT/boot/extlinux"
  extlinux --install "$MOUNT_ROOT/boot/extlinux"

  log "Writing extlinux.conf"
  cat > "$MOUNT_ROOT/boot/extlinux/extlinux.conf" <<EXTCFG
DEFAULT gentooha
PROMPT 0
TIMEOUT 50

LABEL gentooha
  MENU LABEL GentooHA (systemd + HA Supervisor)
  LINUX /boot/${KERNEL_BASENAME}
  INITRD /boot/initramfs-${KERNEL_VERSION}.img
  APPEND root=UUID=${ROOT_UUID} rw ${BASE_BOOT_ARGS} ${DEBUG_BOOT_ARGS} console=tty0
EXTCFG

  log "Writing MBR to image"
  dd if="$MBR_BIN" of="$RAW_FILE" conv=notrunc bs=440 count=1

  umount "$MOUNT_ROOT" || true
  losetup -d "$LOOP_DEV"
  LOOP_DEV=""

  OUT_RAW="$ARTIFACT_DIR/$ARTIFACT_NAME"
  mv "$RAW_FILE" "$OUT_RAW"

  OUT_VDI="${OUT_RAW%.img}.vdi"
  log "Converting raw image to VirtualBox VDI"
  qemu-img convert -f raw -O vdi "$OUT_RAW" "$OUT_VDI"

  log "x64 raw image: $OUT_RAW ($(du -sh "$OUT_RAW" | cut -f1))"
  log "x64 VDI image: $OUT_VDI ($(du -sh "$OUT_VDI" | cut -f1))"

else
  # ARM image path (existing behavior)
  log "Preparing host tools for ARM IMG generation"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y -q >/dev/null
    apt-get install -y -q dosfstools parted rsync >/dev/null
  else
    die "apt-get not found; install dosfstools, parted, rsync manually"
  fi

  IMG_SIZE_MB="${IMG_SIZE_MB:-3072}"
  BOOT_SIZE_MB="${BOOT_SIZE_MB:-256}"
  IMG_FILE="$WORK_DIR/${ARTIFACT_NAME%.img}.raw"

  WORK_PARENT="$(dirname "$IMG_FILE")"
  AVAIL_MB="$(df -Pm "$WORK_PARENT" | awk 'NR==2 {print $4}')"
  NEED_MB="$((IMG_SIZE_MB + 512))"
  if (( AVAIL_MB < NEED_MB )); then
    die "Insufficient space in $WORK_PARENT (${AVAIL_MB}MB free, need at least ${NEED_MB}MB). Set IMG_SIZE_MB lower or free disk space."
  fi

  log "Creating ${IMG_SIZE_MB}MB raw image: $IMG_FILE"
  dd if=/dev/zero of="$IMG_FILE" bs=1M count="$IMG_SIZE_MB" status=progress

  log "Partitioning: ${BOOT_SIZE_MB}MB FAT32 boot + rest ext4 root"
  parted -s "$IMG_FILE" \
    mklabel msdos \
    mkpart primary fat32 1MiB "${BOOT_SIZE_MB}MiB" \
    set 1 boot on \
    mkpart primary ext4 "${BOOT_SIZE_MB}MiB" 100%

  LOOP_DEV="$(losetup -fP --show "$IMG_FILE")"

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
  cp "$KERNEL_IMAGE" "$MOUNT_BOOT/vmlinuz"
  cp "$INITRAMFS_IMAGE" "$MOUNT_BOOT/initramfs.img"
  find "$TARGET_ROOT/boot" -name '*.dtb' -exec cp {} "$MOUNT_BOOT/" \; 2>/dev/null || true

  case "$PLATFORM" in
    pi3|pi4|pizero2)
      cat > "$MOUNT_BOOT/cmdline.txt" <<CMDLINE
root=/dev/mmcblk0p2 rootfstype=ext4 ${BASE_BOOT_ARGS} ${DEBUG_BOOT_ARGS} rootwait console=serial0,115200 console=tty1
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
cmdline=root=/dev/mmcblk0p2 rootfstype=ext4 ${BASE_BOOT_ARGS} ${DEBUG_BOOT_ARGS} rootwait
UENV
      ;;
    pbv2)
      cat > "$MOUNT_BOOT/uEnv.txt" <<UENV
uname_r=${KERNEL_VERSION}
cmdline=root=/dev/mmcblk0p2 rootfstype=ext4 ${BASE_BOOT_ARGS} ${DEBUG_BOOT_ARGS} rootwait
UENV
      ;;
  esac

  umount "$MOUNT_BOOT"
  umount "$MOUNT_ROOT"
  losetup -d "$LOOP_DEV"
  LOOP_DEV=""

  OUT_ARTIFACT="$ARTIFACT_DIR/$ARTIFACT_NAME"
  mv "$IMG_FILE" "$OUT_ARTIFACT"
  log "ARM IMG created: $OUT_ARTIFACT ($(du -sh "$OUT_ARTIFACT" | cut -f1))"
fi

stage_end stage11
