#!/bin/bash
set -e
MNTDIR=/mnt/gentooha_boot

echo "=== Current sshd_config SSH settings ==="
grep -E "PermitRootLogin|PasswordAuthentication|UseDNS|UsePAM|ListenAddress" "$MNTDIR/etc/ssh/sshd_config" || true

# Add/set UseDNS no
if ! grep -q "^UseDNS" "$MNTDIR/etc/ssh/sshd_config"; then
    echo "UseDNS no" >> "$MNTDIR/etc/ssh/sshd_config"
    echo "Added UseDNS no"
else
    sed -i "s/^UseDNS.*/UseDNS no/" "$MNTDIR/etc/ssh/sshd_config"
    echo "Set UseDNS no"
fi

# Ensure PermitRootLogin yes
if grep -q "^#*PermitRootLogin" "$MNTDIR/etc/ssh/sshd_config"; then
    sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" "$MNTDIR/etc/ssh/sshd_config"
else
    echo "PermitRootLogin yes" >> "$MNTDIR/etc/ssh/sshd_config"
fi

# Ensure PasswordAuthentication yes
if grep -q "^#*PasswordAuthentication" "$MNTDIR/etc/ssh/sshd_config"; then
    sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" "$MNTDIR/etc/ssh/sshd_config"
else
    echo "PasswordAuthentication yes" >> "$MNTDIR/etc/ssh/sshd_config"
fi

echo "=== hosts.deny ==="
cat "$MNTDIR/etc/hosts.deny" 2>/dev/null || echo "(not found)"

echo "=== Setting root password ==="
echo "root:gentooha" | chroot "$MNTDIR" chpasswd
echo "Root password set to: gentooha"

echo "=== Final sshd_config relevant lines ==="
grep -E "PermitRootLogin|PasswordAuthentication|UseDNS|UsePAM" "$MNTDIR/etc/ssh/sshd_config"

echo "DONE"
