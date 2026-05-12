#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

stage_start stage8
require_root
mount_chroot_fs
ensure_portage_cache_dirs

log "Refreshing local gentooha overlay in chroot"
rm -rf "$TARGET_ROOT/var/db/repos/gentooha"
mkdir -p "$TARGET_ROOT/var/db/repos/gentooha"
cp -a "$REPO_ROOT/overlay/." "$TARGET_ROOT/var/db/repos/gentooha/"

# Machine type for hassio.json — arch-specific, filled in here at build time.
MACHINE="${MACHINE:-generic-x86-64}"
DATA_SHARE="${DATA_SHARE:-/var/lib/homeassistant}"
HASSIO_CONFIG="/etc/hassio.json"

# Map build PLATFORM to Supervisor image architecture prefix.
case "${PLATFORM:-x64}" in
  x64)          HA_ARCH="amd64" ;;
  pi3|pi4|pbv2) HA_ARCH="aarch64" ;;
  bbb|pizero2)  HA_ARCH="armv7" ;;
  *)            HA_ARCH="amd64" ;;
esac

HASSIO_DOCKER="ghcr.io/home-assistant/${HA_ARCH}-hassio-supervisor"

log "Installing Supervisor and os-agent packages (HomeAssistantFork → upstream fallback)"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u

# Ensure the current overlay checkout is configured and manifested inside the chroot.
mkdir -p /var/tmp /var/db/repos/gentoo /var/db/repos/gentooha /etc/portage/repos.conf
cat >/etc/portage/repos.conf/gentooha.conf <<'EOF'
[gentooha]
location = /var/db/repos/gentooha
masters = gentoo
auto-sync = no
EOF

if command -v ebuild >/dev/null 2>&1 && [[ ! -f /var/db/repos/gentooha/sys-apps/gentooha-os-agent/Manifest ]]; then
  find /var/db/repos/gentooha -mindepth 3 -maxdepth 3 -name '*.ebuild' -print0 | while IFS= read -r -d '' ebuild_file; do
    pkg_dir="$(dirname "$ebuild_file")"
    echo "[stage8] Generating manifest for overlay package: $pkg_dir"
    (cd "$pkg_dir" && ebuild "$(basename "$ebuild_file")" manifest)
  done
fi

# Accept live ebuilds for supervisor and os-agent if not already accepted.
mkdir -p /etc/portage/package.accept_keywords
grep -qxF 'sys-apps/gentooha-supervisor **' /etc/portage/package.accept_keywords/gentooha 2>/dev/null \
  || echo 'sys-apps/gentooha-supervisor **' >> /etc/portage/package.accept_keywords/gentooha
grep -qxF 'sys-apps/gentooha-os-agent **' /etc/portage/package.accept_keywords/gentooha 2>/dev/null \
  || echo 'sys-apps/gentooha-os-agent **' >> /etc/portage/package.accept_keywords/gentooha

emerge --ask=n --noreplace sys-apps/gentooha-supervisor sys-apps/gentooha-os-agent

# Enable Supervisor and os-agent services.
systemctl enable hassio-apparmor.service hassio-supervisor.service os-agent.service
"

# Fill in machine-specific values in hassio.json template (%%MACHINE%% placeholder
# is left by the gentooha-supervisor ebuild so the stage can substitute per-platform).
log "Configuring /etc/hassio.json for MACHINE=${MACHINE} ARCH=${HA_ARCH}"
if [[ -f "${TARGET_ROOT}${HASSIO_CONFIG}" ]]; then
  sed -i \
    -e "s|%%MACHINE%%|${MACHINE}|g" \
    -e "s|ghcr.io/home-assistant/amd64-hassio-supervisor|${HASSIO_DOCKER}|g" \
    "${TARGET_ROOT}${HASSIO_CONFIG}"
else
  mkdir -p "${TARGET_ROOT}/etc"
  cat > "${TARGET_ROOT}${HASSIO_CONFIG}" <<HASSIOJSON
{
    "supervisor": "${HASSIO_DOCKER}",
    "machine": "${MACHINE}",
    "data": "${DATA_SHARE}"
}
HASSIOJSON
fi

# os-release Debian spoof — required by Supervisor preinst checks at first run.
log "Writing Debian-compatible /etc/os-release (Supervisor expects ID=debian)"
cat > "${TARGET_ROOT}/etc/os-release" <<'OSRELEASE'
ID=debian
ID_LIKE=gentoo
VERSION_ID="13"
VERSION="13 (trixie)"
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
NAME="Debian GNU/Linux"
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"
OSRELEASE

# Ensure docker CLI is resolvable at /usr/bin/docker (Supervisor hard-codes this path).
if [[ ! -x "${TARGET_ROOT}/usr/bin/docker" ]]; then
  for candidate in /usr/sbin/docker /bin/docker /usr/local/bin/docker; do
    if [[ -x "${TARGET_ROOT}${candidate}" ]]; then
      mkdir -p "${TARGET_ROOT}/usr/bin"
      ln -sfn "${candidate}" "${TARGET_ROOT}/usr/bin/docker"
      log "Created /usr/bin/docker -> ${candidate} symlink"
      break
    fi
  done
fi

# Ensure data and AppArmor directories exist.
mkdir -p "${TARGET_ROOT}${DATA_SHARE}"
mkdir -p "${TARGET_ROOT}${DATA_SHARE}/apparmor"

log "Stage 8 complete. On first boot:"
log "  1. systemd starts os-agent, docker, hassio-supervisor"
log "  2. hassio-supervisor pulls the Supervisor Docker image"
log "  3. Supervisor bootstraps Home Assistant Core"
log "  Reach HA at http://<host-ip>:8123"

stage_end stage8
