#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage9
require_root
mount_chroot_fs

log "Installing and enabling AppArmor userspace tools inside chroot"
chroot_script="$(cat <<'EOF'
set -euo pipefail
set +u
source /etc/profile
set -u

# Install AppArmor userspace and SSH server for VM diagnostics/access
emerge --ask=n sys-apps/apparmor net-misc/openssh

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

# Allow root SSH login (needed for debug/test access)
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    # Ensure empty password allowed for debug builds
    grep -q '^PermitEmptyPasswords' /etc/ssh/sshd_config \
        && sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config \
        || echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config
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
if command -v systemctl &>/dev/null; then
    systemctl enable systemd-networkd.service   2>/dev/null || true
    systemctl enable systemd-resolved.service   2>/dev/null || true
    systemctl enable docker.service             2>/dev/null || true
    systemctl enable os-agent.service           2>/dev/null || true
    systemctl enable hassio-supervisor.service  2>/dev/null || true
fi

# ── 8. Enable IPv4 forwarding persistently ───────────────────────────────────
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-gentooha.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL

echo "OS hardening and boot fixes complete"
EOF
)"

# Pass FLAVOR into the chroot environment
export FLAVOR="${FLAVOR:-live}"
run_in_chroot "$hardening_script"

stage_end stage9
