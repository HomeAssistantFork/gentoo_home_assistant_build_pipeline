#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage8
require_root

SUPERVISED_INSTALLER_URL="${SUPERVISED_INSTALLER_URL:-https://raw.githubusercontent.com/home-assistant/supervised-installer/main/installer.sh}"
MACHINE="${MACHINE:-generic-x86-64}"
DATA_SHARE="${DATA_SHARE:-/mnt/data/supervisor}"

log "Installing Home Assistant supervised stack"
run_in_chroot "
set -euo pipefail
source /etc/profile
mkdir -p '${DATA_SHARE}'
systemctl start docker || true
curl -fsSL '${SUPERVISED_INSTALLER_URL}' -o /root/installer.sh
bash /root/installer.sh --machine '${MACHINE}' --data-share '${DATA_SHARE}'
"

stage_end stage8
