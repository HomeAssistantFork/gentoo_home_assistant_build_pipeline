#!/usr/bin/env bash
# Unpack a rootfs tarball (produced by rootfs_pack.sh) into TARGET_ROOT,
# then re-mount the chroot virtual filesystems.
# Usage: bash rootfs_unpack.sh [input_path]
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACK_IN="${1:-/tmp/rootfs.tar.zst}"

require_root

[[ -f "$PACK_IN" ]] || die "Rootfs tarball not found: $PACK_IN"

# Install zstd on build host if missing (needed for decompression).
if ! command -v zstd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -q zstd >/dev/null
fi
command -v zstd >/dev/null 2>&1 || die "zstd not found; install it before running rootfs_unpack.sh"

log "Unpacking $PACK_IN → $TARGET_ROOT"
mkdir -p "$(dirname "$TARGET_ROOT")"

tar \
  --use-compress-program='zstd -d' \
  -xpf "$PACK_IN" \
  -C "$(dirname "$TARGET_ROOT")"

log "Mounting chroot virtual filesystems"
mount_chroot_fs

log "Unpack complete: $TARGET_ROOT"
