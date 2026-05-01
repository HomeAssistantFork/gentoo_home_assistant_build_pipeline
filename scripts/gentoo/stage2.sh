#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage2
require_root
require_cmd tar

STAGE3_TARBALL="${STAGE3_TARBALL:-}"
if [[ -z "$STAGE3_TARBALL" ]]; then
  die "Set STAGE3_TARBALL to a Gentoo stage3 tarball path."
fi
[[ -f "$STAGE3_TARBALL" ]] || die "Stage3 tarball not found: $STAGE3_TARBALL"

log "Extracting stage3 into $TARGET_ROOT"
tar xpf "$STAGE3_TARBALL" --xattrs-include='*.*' --numeric-owner -C "$TARGET_ROOT"

log "Copying DNS resolver config"
cp -L /etc/resolv.conf "$TARGET_ROOT/etc/resolv.conf"

log "Mounting filesystems for chroot"
mount_chroot_fs

stage_end stage2
