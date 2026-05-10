#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage4
require_root
mount_chroot_fs

case "${ARCH:-amd64}" in
	x86_64|amd64) PORTAGE_ARCH="amd64" ;;
	arm64|aarch64) PORTAGE_ARCH="arm64" ;;
	arm)           PORTAGE_ARCH="arm" ;;
	*)             PORTAGE_ARCH="${ARCH:-amd64}" ;;
esac

log "Installing GentooHA alpha meta-package (pulls Docker, AppArmor, Supervisor, os-agent, openssh, grub, and all deps)"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u

# Ensure the Gentoo tree exists in the restored rootfs.  Some stage3 artifacts
# may not carry a populated /var/db/repos/gentoo, which leaves Portage unable
# to resolve profiles or masks.
mkdir -p /var/db/repos/gentoo /var/db/repos/gentooha /etc/portage/repos.conf
[[ -d /var/db/repos/gentoo/profiles ]] || {
	echo "[stage4] Seeding Gentoo repository metadata"
	emerge-webrsync
}

# Allow live (~9999) and testing ebuilds required by the meta-package.
mkdir -p /etc/portage/package.accept_keywords
cat >/etc/portage/package.accept_keywords/gentooha <<'EOF'
app-containers/docker ~${PORTAGE_ARCH}
app-emulation/qemu ~${PORTAGE_ARCH}
sys-kernel/gentooha-kernel-config-alpha **
sys-apps/gentooha-compat **
sys-apps/gentooha-supervisor **
sys-apps/gentooha-os-agent **
gentooha/gentooha-alpha **
EOF

# Overlay USE flag overrides for Docker storage driver.
mkdir -p /etc/portage/package.use
cat >/etc/portage/package.use/docker <<'EOF'
app-containers/docker overlay
EOF

# Emerge the meta-package; Portage resolves all sub-packages as deps.
# Override EMERGE_DEFAULT_OPTS: the make.conf from stage3 sets --usepkgonly for
# ARM qemu safety, but our custom overlay packages have no binary packages and
# must be built from source.  --usepkg allows binary packages where available
# and falls back to source for overlay ebuilds (which are mostly file installs
# with no compilation except gentooha-os-agent which uses Go).
EMERGE_DEFAULT_OPTS="" emerge --ask=n --getbinpkg --usepkg --binpkg-respect-use=y gentooha/gentooha-alpha

# Ensure Docker starts on boot.
systemctl enable docker

# Ensure compat sync service is enabled.
systemctl enable ha-os-release-sync.service
"

stage_end stage4
