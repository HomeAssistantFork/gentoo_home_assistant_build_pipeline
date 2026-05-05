#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage4
require_root
mount_chroot_fs

log "Installing container runtime and Supervisor host dependencies"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u

mkdir -p /etc/portage/package.accept_keywords
cat >/etc/portage/package.accept_keywords/ha-supervisor <<'EOF'
app-containers/docker ~amd64
app-emulation/qemu ~amd64
EOF

mkdir -p /etc/portage/package.use
cat >/etc/portage/package.use/docker <<'EOF'
app-containers/docker overlay
EOF

emerge --ask=n --noreplace \
  app-containers/docker \
  net-firewall/iptables \
  app-arch/xz-utils \
  app-misc/jq \
  net-misc/curl \
  dev-vcs/git

systemctl enable docker
"

stage_end stage4
