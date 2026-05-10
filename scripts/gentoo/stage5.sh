#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage5
require_root
mount_chroot_fs

log "Installing GentooHA compat layer (sys-apps/gentooha-compat)"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u

# gentooha-compat is pulled as a dep of gentooha-alpha in stage4, but emerge
# --noreplace makes this a no-op if already installed so the stage is safe to
# run standalone when skipping stage4.
emerge --ask=n --noreplace sys-apps/gentooha-compat

systemctl enable ha-os-release-sync.service
"

stage_end stage5
