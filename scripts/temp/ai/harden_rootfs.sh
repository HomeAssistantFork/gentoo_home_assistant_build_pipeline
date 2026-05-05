#!/bin/bash
set -e
G=/mnt/gentoo

# 1. machine-id
if [ ! -s "$G/etc/machine-id" ]; then
    cat /proc/sys/kernel/random/uuid | tr -d '-' > "$G/etc/machine-id"
fi
echo "machine-id: $(cat $G/etc/machine-id)"
mkdir -p "$G/var/lib/dbus"
[ -e "$G/var/lib/dbus/machine-id" ] || ln -sf /etc/machine-id "$G/var/lib/dbus/machine-id"

# 2. mask firstboot
mkdir -p "$G/etc/systemd/system"
ln -sf /dev/null "$G/etc/systemd/system/systemd-firstboot.service"
echo "firstboot: masked"

# 3. autologin tty1
mkdir -p "$G/etc/systemd/system/getty@tty1.service.d"
cat > "$G/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF
echo "autologin: configured"

# 4. sysctl
mkdir -p "$G/etc/sysctl.d"
echo 'net.ipv4.ip_forward = 1' > "$G/etc/sysctl.d/99-gentooha.conf"

# 5. enable services
WANTS="$G/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
for svc in systemd-networkd systemd-resolved docker os-agent hassio-supervisor sshd ssh; do
    f=$(find "$G/usr/lib/systemd/system" "$G/etc/systemd/system" -name "${svc}.service" 2>/dev/null | head -1)
    [ -z "$f" ] && continue
    rel="${f#$G}"
    ln -sf "$rel" "$WANTS/${svc}.service" 2>/dev/null && echo "enabled: $svc" || true
done

echo "ALL DONE"
