#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage9
require_root

log "Installing and enabling AppArmor userspace tools inside chroot"
chroot_script="$(cat <<'EOF'
set -euo pipefail
set +u
source /etc/profile
set -u

# Install AppArmor userspace (provides apparmor_parser, aa-status, aa-enforce, etc.)
emerge --ask=n sys-apps/apparmor

# Enable the AppArmor systemd service so profiles load on boot
if command -v systemctl &>/dev/null; then
    systemctl enable apparmor.service
    echo "AppArmor service enabled via systemctl"
elif command -v rc-update &>/dev/null; then
    rc-update add apparmor boot
    echo "AppArmor service added to OpenRC boot runlevel"
else
    echo "WARNING: Neither systemctl nor rc-update found; enable apparmor service manually" >&2
fi

# Verify apparmor_parser is available
if command -v apparmor_parser &>/dev/null; then
    echo "apparmor_parser: $(apparmor_parser --version 2>&1 | head -1)"
else
    echo "ERROR: apparmor_parser not found after install" >&2
    exit 1
fi

echo "AppArmor userspace setup complete"
EOF
)"

run_in_chroot "$chroot_script"

stage_end stage9
