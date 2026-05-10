#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage9
require_root
mount_chroot_fs

log "Installing AppArmor userspace tools and openssh (if not already present via meta-package)"
chroot_script="$(cat <<'EOF'
set -euo pipefail
set +u
source /etc/profile
set -u

# sys-apps/apparmor and net-misc/openssh are deps of gentooha-alpha (stage4).
# Use --noreplace so this is a no-op on a full build; installs them on partial runs.
emerge --ask=n --noreplace sys-apps/apparmor net-misc/openssh

# Ensure Docker CLI is present.
if ! command -v docker &>/dev/null; then
    emerge --ask=n --noreplace app-containers/docker-cli \
        || emerge --ask=n --noreplace app-containers/moby-cli \
        || true
fi

if ! command -v docker &>/dev/null; then
    if [ -x /usr/sbin/docker ] && [ ! -e /usr/bin/docker ]; then
        ln -s /usr/sbin/docker /usr/bin/docker
    elif [ -x /bin/docker ] && [ ! -e /usr/bin/docker ]; then
        ln -s /bin/docker /usr/bin/docker
    fi
fi

# Enable the AppArmor systemd service so profiles load on boot.
if command -v systemctl &>/dev/null; then
    systemctl enable apparmor.service
    echo "AppArmor service enabled"
fi

# Verify apparmor_parser is available.
if command -v apparmor_parser &>/dev/null; then
    echo "apparmor_parser: $(apparmor_parser --version 2>&1 | head -1)"
else
    echo "ERROR: apparmor_parser not found after install" >&2
    exit 1
fi

echo "AppArmor and openssh setup complete"
EOF
)"

run_in_chroot "$chroot_script"

log "Applying OS hardening and boot fixes inside chroot"
hardening_script="$(cat <<'EOF'
set -euo pipefail

# ── 1. Fix systemd-firstboot deadlock ─────────────────────────────────────────
# Generate machine-id so firstboot has nothing to do and exits immediately
if [ ! -s /etc/machine-id ]; then
    systemd-machine-id-setup 2>/dev/null || \
    dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || \
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id
    echo "machine-id generated: $(cat /etc/machine-id)"
fi

# Ensure dbus machine-id symlink
mkdir -p /var/lib/dbus
if [ ! -e /var/lib/dbus/machine-id ]; then
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

# Mask systemd-firstboot so it never blocks boot again
if command -v systemctl &>/dev/null; then
    systemctl mask systemd-firstboot.service || true
    echo "systemd-firstboot masked"
fi

# ── 2. Ensure /etc/hostname and /etc/locale.conf are set ─────────────────────
[ -s /etc/hostname ] || echo "gentooha" > /etc/hostname
[ -s /etc/locale.conf ] || echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ── 3. Enable openssh so SSH works on boot ───────────────────────────────────
if [ ! -x /usr/sbin/sshd ] && [ ! -x /usr/bin/sshd ]; then
    echo "ERROR: openssh installed but sshd binary not found" >&2
    exit 1
fi

if command -v systemctl &>/dev/null; then
    systemctl enable sshd.service 2>/dev/null || \
    systemctl enable ssh.service 2>/dev/null || \
    echo "WARNING: sshd service unit not found, SSH may not start on boot"
fi

# Allow root SSH login (needed for debug/test access).
# Gentoo's PAM snippet can override the main config, so write a late drop-in.
if [ -d /etc/ssh/sshd_config.d ]; then
    cat > /etc/ssh/sshd_config.d/zzz-gentooha-debug.conf <<'SSHCFG'
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords yes
UseDNS no
UsePAM no
SSHCFG
elif [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    grep -q '^PermitEmptyPasswords' /etc/ssh/sshd_config \
        && sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config \
        || echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config
    grep -q '^UseDNS' /etc/ssh/sshd_config \
        && sed -i 's/^UseDNS.*/UseDNS no/' /etc/ssh/sshd_config \
        || echo "UseDNS no" >> /etc/ssh/sshd_config
fi

# ── 4. Set root password to empty for debug builds ───────────────────────────
passwd -d root 2>/dev/null || true
echo "root::0:0:root:/root:/bin/bash" | chpasswd -e 2>/dev/null || true
# Alternative: set known password 'gentooha' for safety
echo "root:gentooha" | chpasswd 2>/dev/null || true

# ── 5. Enable autologin on tty1 for debug flavor ─────────────────────────────
if [ "${FLAVOR:-live}" = "debug" ]; then
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
AUTOLOGIN
    echo "Autologin on tty1 enabled for debug flavor"
fi

# ── 6. Enable persistent journald storage ────────────────────────────────────
mkdir -p /var/log/journal
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-persistent.conf <<'JCONF'
[Journal]
Storage=persistent
Compress=yes
JCONF

# ── 7. Enable key services ───────────────────────────────────────────────────
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired-dhcp.network <<'NETWORKD'
[Match]
Name=en* eth*

[Network]
DHCP=yes
LinkLocalAddressing=ipv6
IPv6AcceptRA=yes
NETWORKD

# ── 7b. Configure DNS via systemd-resolved ───────────────────────────────────
# Replace any WSL-generated resolv.conf with the systemd-resolved stub so that
# DNS servers received via DHCP (e.g. VirtualBox NAT 10.0.2.3) are used.
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf


if command -v systemctl &>/dev/null; then
    systemctl enable getty@tty1.service          2>/dev/null || true
    systemctl enable serial-getty@ttyS0.service  2>/dev/null || true
    systemctl enable systemd-networkd.service   2>/dev/null || true
    systemctl enable systemd-resolved.service   2>/dev/null || true
    systemctl enable docker.service             2>/dev/null || true
    systemctl enable os-agent.service           2>/dev/null || true
    systemctl enable hassio-supervisor.service  2>/dev/null || true
    
    # Disable the network-online blocking service (problematic in containers/WSL)
    systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
    
    # Set timeout on networkd to prevent indefinite wait
    mkdir -p /etc/systemd/system/systemd-networkd.service.d
    cat > /etc/systemd/system/systemd-networkd.service.d/timeout.conf <<'TIMEOUT'
[Service]
TimeoutStartSec=10s
TimeoutStopSec=5s
TIMEOUT
fi

# ── 8. Enable IPv4 forwarding persistently ───────────────────────────────────
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-gentooha.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL

# ── 9. Systemd/Docker VM compatibility knobs ─────────────────────────────────
# Some host kernels (including certain VM setups) do not expose all cgroup2
# controllers/attributes that newer systemd defaults may try to write.
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-gentooha-compat.conf <<'SCONF'
[Manager]
DefaultTimeoutStartSec=1min
DefaultTimeoutStopSec=1min
DefaultCPUAccounting=no
DefaultMemoryAccounting=no
DefaultTasksAccounting=no
DefaultIOAccounting=no
DefaultIPAccounting=no
DefaultCPUQuota=
DefaultMemoryZSwapMax=
SCONF

# Force a conservative Docker setup for broad VM compatibility.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKERJSON'
{
    "storage-driver": "vfs",
    "log-driver": "json-file",
    "iptables": false,
    "ip6tables": false,
    "ipv6": false,
    "ip-masq": false,
    "bridge": "none",
    "debug": true
}
DOCKERJSON

mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/99-gentooha-compat.conf <<'DCONF'
[Unit]
StartLimitIntervalSec=2min
StartLimitBurst=2

[Service]
CPUQuota=
CPUWeight=
MemoryMax=
MemoryHigh=
MemorySwapMax=
MemoryZSwapMax=
TimeoutStartSec=1min
TimeoutStopSec=1min
TasksMax=infinity
Delegate=yes
StandardOutput=journal+console
StandardError=journal+console
DCONF

mkdir -p /etc/systemd/system/hassio-supervisor.service.d
cat > /etc/systemd/system/hassio-supervisor.service.d/99-gentooha-compat.conf <<'HCONF'
[Unit]
StartLimitIntervalSec=2min
StartLimitBurst=2

[Service]
TimeoutStartSec=1min
TimeoutStopSec=1min
Restart=on-failure
RestartSec=5s
StandardOutput=journal+console
StandardError=journal+console
HCONF

echo "OS hardening and boot fixes complete"
EOF
)"

# Pass FLAVOR into the chroot environment
export FLAVOR="${FLAVOR:-live}"
run_in_chroot "$hardening_script"

stage_end stage9
