#!/usr/bin/env bash
# Unpack a rootfs tarball created by rootfs_pack.sh into TARGET_ROOT.
# Usage: bash rootfs_unpack.sh [input_path]
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACK_IN="${1:-/tmp/rootfs.tar.zst}"

require_root
[[ -f "$PACK_IN" ]] || die "Rootfs tarball not found: $PACK_IN"

if ! command -v zstd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt-get update -y -q >/dev/null
  apt-get install -y -q zstd >/dev/null
fi
command -v zstd >/dev/null 2>&1 || die "zstd not found; install it before running rootfs_unpack.sh"

log "Unpacking $PACK_IN -> $TARGET_ROOT"
mkdir -p "$(dirname "$TARGET_ROOT")"

tar \
  --use-compress-program='zstd -d' \
  -xpf "$PACK_IN" \
  -C "$(dirname "$TARGET_ROOT")"

# Stage jobs run on fresh runners; re-prepare binfmt/qemu for ARM chroots each time.
case "${ARCH:-}" in
  arm|armv7|armv7a)
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install qemu-user-static binfmt-support >/dev/null
    fi
    command -v update-binfmts >/dev/null 2>&1 && update-binfmts --enable qemu-arm 2>/dev/null || true
    if [[ -x /usr/bin/qemu-arm-static ]]; then
      mkdir -p "$TARGET_ROOT/usr/bin"
      cp -f /usr/bin/qemu-arm-static "$TARGET_ROOT/usr/bin/"
    fi
    ;;
  arm64|aarch64)
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get -y -q install qemu-user-static binfmt-support >/dev/null
    fi
    command -v update-binfmts >/dev/null 2>&1 && update-binfmts --enable qemu-aarch64 2>/dev/null || true
    if [[ -x /usr/bin/qemu-aarch64-static ]]; then
      mkdir -p "$TARGET_ROOT/usr/bin"
      cp -f /usr/bin/qemu-aarch64-static "$TARGET_ROOT/usr/bin/"
    fi
    ;;
esac

log "Mounting chroot virtual filesystems"
mount_chroot_fs

_META="$(dirname "$PACK_IN")/rootfs_meta.txt"
if [[ -f "$STATE_ROOT/completed_stage" ]]; then
  _COMPLETED_STAGE="$(cat "$STATE_ROOT/completed_stage")"
  printf 'COMPLETED_STAGE=%s\n' "$_COMPLETED_STAGE" > "$_META"
  log "Restored rootfs with completed_stage=$_COMPLETED_STAGE"
else
  rm -f "$_META"
  log "No completed_stage marker in rootfs"
fi
unset _META _COMPLETED_STAGE

log "Unpack complete: $TARGET_ROOT"
