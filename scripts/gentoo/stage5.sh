#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

stage_start stage5
require_root
mount_chroot_fs

log "Refreshing local gentooha overlay in chroot"
rm -rf "$TARGET_ROOT/var/db/repos/gentooha"
mkdir -p "$TARGET_ROOT/var/db/repos/gentooha"
cp -a "$REPO_ROOT/overlay/." "$TARGET_ROOT/var/db/repos/gentooha/"

log "Installing GentooHA compat layer (sys-apps/gentooha-compat)"
run_in_chroot "$(cat <<'CHROOT_STAGE5'
set -euo pipefail
set +u
source /etc/profile
set -u

case "${ARCH:-amd64}" in
	x86_64|amd64) PORTAGE_ARCH="amd64" ;;
	arm64|aarch64) PORTAGE_ARCH="arm64" ;;
	arm) PORTAGE_ARCH="arm" ;;
	*) PORTAGE_ARCH="${ARCH:-amd64}" ;;
esac

# Stage artifacts may not retain a populated Gentoo tree or /var/tmp.
mkdir -p /var/tmp /var/db/repos/gentoo /var/db/repos/gentooha /etc/portage/repos.conf
if [[ ! -d /var/db/repos/gentoo/profiles ]]; then
	echo "[stage5] Seeding Gentoo repository metadata"
	emerge-webrsync
fi

cat >/etc/portage/repos.conf/gentooha.conf <<'EOF'
[gentooha]
location = /var/db/repos/gentooha
masters = gentoo
auto-sync = no
EOF

if command -v ebuild >/dev/null 2>&1 && [[ ! -f /var/db/repos/gentooha/sys-apps/gentooha-compat/Manifest ]]; then
	find /var/db/repos/gentooha -mindepth 3 -maxdepth 3 -name '*.ebuild' -print0 | while IFS= read -r -d '' ebuild_file; do
		pkg_dir="$(dirname "$ebuild_file")"
		echo "[stage5] Generating manifest for overlay package: $pkg_dir"
		(cd "$pkg_dir" && ebuild "$(basename "$ebuild_file")" manifest)
	done
fi

mkdir -p /etc/portage/package.accept_keywords
cat >/etc/portage/package.accept_keywords/gentooha <<EOF
app-containers/docker ~${PORTAGE_ARCH}
app-containers/containerd ~${PORTAGE_ARCH}
app-containers/runc ~${PORTAGE_ARCH}
app-emulation/qemu ~${PORTAGE_ARCH}
dev-go/go-md2man ~${PORTAGE_ARCH}
sys-apps/gentooha-compat **
EOF

# gentooha-compat is pulled as a dep of gentooha-alpha in stage4, but emerge
# --noreplace makes this a no-op if already installed so the stage is safe to
# run standalone when skipping stage4.
EMERGE_DEFAULT_OPTS="" emerge --ask=n --getbinpkg --usepkg --binpkg-respect-use=y --noreplace sys-apps/gentooha-compat

systemctl enable ha-os-release-sync.service
CHROOT_STAGE5
)"

stage_end stage5
