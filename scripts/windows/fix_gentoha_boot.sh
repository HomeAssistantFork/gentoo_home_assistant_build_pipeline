#!/usr/bin/env bash
# Fix GentooHA WSL2 boot hang
# Run this inside Debian: wsl -d Debian -u root -- bash /mnt/c/Users/tamus/projects/linux/home_assistant_1/scripts/windows/fix_gentoha_boot.sh

set -euo pipefail

GENTOO=/mnt/gentoo

echo "=== Mounting Gentoo proc/sys/dev if needed ==="
mountpoint -q "$GENTOO/proc" || mount -t proc /proc "$GENTOO/proc"
mountpoint -q "$GENTOO/sys"  || mount --rbind /sys "$GENTOO/sys"
mountpoint -q "$GENTOO/dev"  || mount --rbind /dev "$GENTOO/dev"

echo "=== Fixing iptables to legacy mode (required for Docker in WSL2) ==="
# Install iptables-legacy if not present
chroot "$GENTOO" emerge --noreplace --quiet net-firewall/iptables 2>/dev/null || true
# Set alternatives if available
chroot "$GENTOO" bash -c "
  if command -v update-alternatives &>/dev/null; then
    update-alternatives --set iptables  /usr/sbin/iptables-legacy  2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
  fi
  # Symlink approach for Gentoo which doesn't use update-alternatives for iptables
  if [ -f /usr/sbin/iptables-legacy ] && [ ! -L /usr/sbin/iptables ]; then
    ln -sf /usr/sbin/iptables-legacy  /usr/sbin/iptables  || true
    ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables || true
  fi
  echo IPTABLES_DONE
"

echo "=== Disabling hassio-supervisor and hassio-apparmor auto-start ==="
# We'll re-enable after Docker is confirmed stable
rm -f "$GENTOO/etc/systemd/system/multi-user.target.wants/hassio-supervisor.service"
rm -f "$GENTOO/etc/systemd/system/multi-user.target.wants/hassio-apparmor.service"
echo "HA services disabled from auto-start"

echo "=== Writing Docker daemon config for WSL2 compatibility ==="
mkdir -p "$GENTOO/etc/docker"
cat > "$GENTOO/etc/docker/daemon.json" <<'DOCKEREOF'
{
  "storage-driver": "overlay2",
  "iptables": true,
  "bridge": "none",
  "log-driver": "journald"
}
DOCKEREOF
echo "Docker daemon.json written"

echo "=== Verifying GentooHA wsl.conf has systemd enabled ==="
cat "$GENTOO/etc/wsl.conf" || echo "(no wsl.conf found)"

echo ""
echo "=== Fix complete. Next steps ==="
echo "1. Run: wsl -d GentooHA"
echo "2. Inside GentooHA: systemctl start docker"
echo "3. Verify: systemctl status docker"
echo "4. If Docker is healthy, re-enable HA services:"
echo "   systemctl enable hassio-apparmor hassio-supervisor"
echo "   systemctl start hassio-apparmor hassio-supervisor"
