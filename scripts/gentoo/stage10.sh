#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage10_internal
require_root
mount_chroot_fs

log "Running internal cleanup in target root to reduce artifact size"
run_in_chroot "
set -euo pipefail
shopt -s nullglob
for x in \
  /usr/src/linux \
  /usr/src/linux-* \
  /usr/src/gentoo-sources-* \
  /var/tmp/portage \
  /var/cache/distfiles \
  /var/cache/binpkgs; do
  if [ -e \"\$x\" ]; then
    rm -rf \"\$x\"
    echo \"CLEANED=\$x\"
  fi
done
"

if [[ "${CLEAN_PORTAGE_TREE:-false}" == "true" ]]; then
  log "CLEAN_PORTAGE_TREE=true -> removing /var/db/repos/gentoo (restorable via emerge --sync)"
  run_in_chroot "rm -rf /var/db/repos/gentoo || true"
fi

stage_end stage10_internal
