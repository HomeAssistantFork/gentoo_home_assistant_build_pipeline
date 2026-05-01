#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage1
require_root

log "Installing host prerequisites (Debian bootstrap host path)."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install \
    debootstrap gdisk parted wget curl git rsync xz-utils tar
else
  warn "apt-get not found. Install host tools manually for your distro."
fi

log "Preparing TARGET_ROOT at $TARGET_ROOT"
mkdir -p "$TARGET_ROOT"
mkdir -p "$TARGET_ROOT"/{etc,usr,var,boot,home,root,tmp}
chmod 1777 "$TARGET_ROOT/tmp"

log "Stage1 host preparation complete."
stage_end stage1
