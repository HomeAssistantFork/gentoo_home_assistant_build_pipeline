#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage5
require_root
mount_chroot_fs

log "Creating Supervisor compatibility identity layer"
chroot_script="$(cat <<'EOF'
set -euo pipefail
mkdir -p /etc/ha-compat /usr/local/bin /etc/systemd/system /mnt/data /run/supervisor

cat >/etc/ha-compat/os-release <<'INNER_EOF'
NAME=Home Assistant OS Compatibility Layer
ID=homeassistant
VERSION=Gentoo-Compatible
VERSION_ID=rolling
PRETTY_NAME=Home Assistant Compatible Gentoo Host
CPE_NAME=cpe:/o:home-assistant:home-assistant-os:compat
HOME_URL=https://www.home-assistant.io/
SUPERVISOR=1
INNER_EOF

cat >/usr/local/bin/ha-host-info <<'INNER_EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'board=%s\n' "$(uname -m)"
printf 'kernel=%s\n' "$(uname -r)"
printf 'operating_system=%s\n' "Home Assistant Compatible Gentoo"
printf 'supported=%s\n' "true"
INNER_EOF
chmod +x /usr/local/bin/ha-host-info

cat >/usr/local/bin/ha-os-release-sync <<'INNER_EOF'
#!/usr/bin/env bash
set -euo pipefail
install -Dm0644 /etc/ha-compat/os-release /run/os-release
INNER_EOF
chmod +x /usr/local/bin/ha-os-release-sync

cat >/etc/systemd/system/ha-os-release-sync.service <<'INNER_EOF'
[Unit]
Description=Sync Home Assistant compatibility os-release to runtime path
After=local-fs.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ha-os-release-sync
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
INNER_EOF

systemctl enable ha-os-release-sync.service
EOF
)"

run_in_chroot "$chroot_script"

stage_end stage5
