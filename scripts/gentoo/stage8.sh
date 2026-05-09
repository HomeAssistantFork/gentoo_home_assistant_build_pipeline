#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage8
require_root

MACHINE="${MACHINE:-generic-x86-64}"
DATA_SHARE="${DATA_SHARE:-/var/lib/homeassistant}"
HASSIO_CONFIG="/etc/hassio.json"
WORK_DIR="/tmp/ha-stage8-$$"
DEB_EXTRACT_DIR="${WORK_DIR}/extract"

# GitHub release URLs (resolved at runtime to always pick latest)
SUPERVISED_DEB_URL="${SUPERVISED_DEB_URL:-https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb}"

# os-agent release assets include the version in the filename so we resolve dynamically
if [[ -z "${OS_AGENT_DEB_URL:-}" ]]; then
    log "Resolving latest os-agent release URL"
    OS_AGENT_DEB_URL=$(curl -fsSL "https://api.github.com/repos/home-assistant/os-agent/releases/latest" \
        | jq -r '.assets[] | select(.name | test("x86_64.*\\.deb$")) | .browser_download_url')
    log "os-agent URL: ${OS_AGENT_DEB_URL}"
fi

cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

# Ensure rsync is available on Debian host for symlink-safe chroot copy
if ! command -v rsync &>/dev/null; then
    log "Installing rsync on build host"
    apt-get install -y -q rsync
fi

mkdir -p "${WORK_DIR}" "${DEB_EXTRACT_DIR}/supervised" "${DEB_EXTRACT_DIR}/os-agent"

# Step 1: Download both .deb packages on the Debian host (not inside chroot)
log "Downloading homeassistant-supervised.deb"
curl -fsSL "${SUPERVISED_DEB_URL}" -o "${WORK_DIR}/homeassistant-supervised.deb"

log "Downloading os-agent .deb"
curl -fsSL "${OS_AGENT_DEB_URL}" -o "${WORK_DIR}/os-agent.deb"

# Step 2: Extract .deb packages into work directory using dpkg-deb (available on Debian host)
log "Extracting homeassistant-supervised.deb"
dpkg-deb --extract "${WORK_DIR}/homeassistant-supervised.deb" "${DEB_EXTRACT_DIR}/supervised"

log "Extracting os-agent .deb"
dpkg-deb --extract "${WORK_DIR}/os-agent.deb" "${DEB_EXTRACT_DIR}/os-agent"

# Step 3: Copy extracted files into the Gentoo chroot
# rsync follows symlinks at the destination (e.g. /usr/sbin -> /usr/bin in Gentoo)
log "Copying supervised-installer files into Gentoo chroot"
rsync -a "${DEB_EXTRACT_DIR}/supervised/" "${TARGET_ROOT}/"

log "Copying os-agent files into Gentoo chroot"
rsync -a "${DEB_EXTRACT_DIR}/os-agent/" "${TARGET_ROOT}/"

# Step 4: Set up os-release spoof to exactly match what preinst checks
# preinst checks: ID=debian, VERSION_ID="13"
log "Configuring os-release compatibility identity"
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

# Step 5: Configure hassio.json (Supervisor runtime config)
log "Writing /etc/hassio.json"
ARCH="amd64"
HASSIO_DOCKER="ghcr.io/home-assistant/${ARCH}-hassio-supervisor"

mkdir -p "${TARGET_ROOT}/etc"
cat > "${TARGET_ROOT}${HASSIO_CONFIG}" <<HASSIOJSON
{
    "supervisor": "${HASSIO_DOCKER}",
    "machine": "${MACHINE}",
    "data": "${DATA_SHARE}"
}
HASSIOJSON

# Step 6: Wire up hassio-supervisor startup script substitution variables
# These placeholder replacements normally happen in postinst — do them here
log "Patching hassio-supervisor and hassio-apparmor scripts"

DOCKER_CLI_PATH="/usr/bin/docker"
if [[ ! -x "${TARGET_ROOT}${DOCKER_CLI_PATH}" ]]; then
    for candidate in /usr/sbin/docker /bin/docker /usr/local/bin/docker; do
        if [[ -x "${TARGET_ROOT}${candidate}" ]]; then
            DOCKER_CLI_PATH="${candidate}"
            break
        fi
    done
fi

for f in \
    "${TARGET_ROOT}/usr/sbin/hassio-supervisor" \
    "${TARGET_ROOT}/usr/sbin/hassio-apparmor" \
    "${TARGET_ROOT}/etc/systemd/system/hassio-supervisor.service" \
    "${TARGET_ROOT}/etc/systemd/system/hassio-apparmor.service"
do
    if [[ -f "$f" ]]; then
        sed -i \
            "s|%%HASSIO_CONFIG%%|${HASSIO_CONFIG}|g;
             s|%%BINARY_DOCKER%%|${DOCKER_CLI_PATH}|g;
             s|%%SERVICE_DOCKER%%|docker.service|g;
             s|%%BINARY_HASSIO%%|/usr/sbin/hassio-supervisor|g;
             s|%%HASSIO_APPARMOR_BINARY%%|/usr/sbin/hassio-apparmor|g" \
            "$f"
    fi
done

# The supervised installer expects an AppArmor profile named
# "hassio-supervisor" which is not shipped in this Gentoo-based image.
# Use unconfined mode to avoid startup failure on profile switch.
if [[ -f "${TARGET_ROOT}/usr/sbin/hassio-supervisor" ]]; then
    sed -i \
        -e 's|--security-opt apparmor="hassio-supervisor"|--security-opt apparmor=unconfined|g' \
        -e 's|--security-opt apparmor=hassio-supervisor|--security-opt apparmor=unconfined|g' \
        "${TARGET_ROOT}/usr/sbin/hassio-supervisor"
fi

# Supervisor units/scripts often assume /usr/bin/docker. Create a compatibility
# symlink when the CLI lives elsewhere in this image.
if [[ ! -x "${TARGET_ROOT}/usr/bin/docker" && -x "${TARGET_ROOT}${DOCKER_CLI_PATH}" ]]; then
    mkdir -p "${TARGET_ROOT}/usr/bin"
    ln -sfn "${DOCKER_CLI_PATH}" "${TARGET_ROOT}/usr/bin/docker"
fi

chmod a+x "${TARGET_ROOT}/usr/sbin/hassio-supervisor" 2>/dev/null || true
chmod a+x "${TARGET_ROOT}/usr/sbin/hassio-apparmor" 2>/dev/null || true
chmod a+x "${TARGET_ROOT}/usr/bin/ha" 2>/dev/null || true

# Step 7: Create required directories
log "Creating required data and apparmor directories"
mkdir -p "${TARGET_ROOT}${DATA_SHARE}"
mkdir -p "${TARGET_ROOT}${DATA_SHARE}/apparmor"

# Write os-agent.service (not included in the .deb, must be created manually)
log "Creating os-agent.service"
mkdir -p "${TARGET_ROOT}/usr/lib/systemd/system"
cat > "${TARGET_ROOT}/usr/lib/systemd/system/os-agent.service" <<'OASERVICE'
[Unit]
Description=Home Assistant OS Agent
Documentation=https://github.com/home-assistant/os-agent
After=dbus.service
Requires=dbus.service

[Service]
Type=dbus
BusName=io.hass.os
ExecStart=/usr/bin/os-agent
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
OASERVICE

# Step 8: Enable systemd services via symlinks (replaces systemctl enable in chroot)
log "Enabling systemd services"
WANTS_DIR="${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS_DIR}"

for svc in os-agent.service hassio-supervisor.service hassio-apparmor.service; do
    # Look in both /etc/systemd/system and /usr/lib/systemd/system
    svc_path=""
    for search_dir in \
        "${TARGET_ROOT}/etc/systemd/system" \
        "${TARGET_ROOT}/usr/lib/systemd/system"; do
        if [[ -f "${search_dir}/${svc}" ]]; then
            svc_path="${search_dir}/${svc}"
            # Symlink target should be relative to /etc/systemd/system/
            # For /usr/lib, use absolute path
            if [[ "${search_dir}" == *"usr/lib"* ]]; then
                link_target="/usr/lib/systemd/system/${svc}"
            else
                link_target="/etc/systemd/system/${svc}"
            fi
            break
        fi
    done

    if [[ -n "${svc_path}" ]]; then
        ln -sfn "${link_target}" "${WANTS_DIR}/${svc}"
        log "Enabled ${svc}"
    else
        warn "Service file not found, skipping: ${svc}"
    fi
done

# Step 9: Kernel dmesg access (written to sysctl.d for first-boot application)
log "Configuring kernel.dmesg_restrict=0 for Supervisor access"
mkdir -p "${TARGET_ROOT}/etc/sysctl.d"
echo "kernel.dmesg_restrict=0" > "${TARGET_ROOT}/etc/sysctl.d/80-hassio.conf"

# Step 10: Docker daemon configuration from package
if [[ -f "${DEB_EXTRACT_DIR}/supervised/etc/docker/daemon.json" ]]; then
    mkdir -p "${TARGET_ROOT}/etc/docker"
    cp "${DEB_EXTRACT_DIR}/supervised/etc/docker/daemon.json" "${TARGET_ROOT}/etc/docker/daemon.json"
    if grep -q '"ip6tables"' "${TARGET_ROOT}/etc/docker/daemon.json"; then
        sed -i 's/"ip6tables"[[:space:]]*:[[:space:]]*true/"ip6tables": false/g' "${TARGET_ROOT}/etc/docker/daemon.json"
    fi
    if ! grep -q '"iptables"' "${TARGET_ROOT}/etc/docker/daemon.json"; then
        sed -i '/"ip6tables"[[:space:]]*:/a\    "iptables": false,' "${TARGET_ROOT}/etc/docker/daemon.json"
    else
        sed -i 's/"iptables"[[:space:]]*:[[:space:]]*true/"iptables": false/g' "${TARGET_ROOT}/etc/docker/daemon.json"
    fi
    log "Installed Docker daemon.json"
fi

log "Stage 8 complete. On first boot:"
log "  1. systemd starts os-agent, docker, hassio-supervisor"
log "  2. hassio-supervisor pulls the Supervisor Docker image"
log "  3. Supervisor bootstraps Home Assistant Core"
log "  Reach HA at http://<host-ip>:8123"

stage_end stage8
