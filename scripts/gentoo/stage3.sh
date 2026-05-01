#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage3
require_root

GENTOO_PROFILE="${GENTOO_PROFILE:-default/linux/amd64/23.0/systemd}"
TIMEZONE="${TIMEZONE:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8 UTF-8}"
HOSTNAME="${HOSTNAME_OVERRIDE:-ha-gentoo}"
LANG_NAME="${LOCALE%% *}"

log "Configuring portage and system profile inside chroot"
run_in_chroot "
set -euo pipefail
set +u
source /etc/profile
set -u
emerge-webrsync
if ! command -v eselect >/dev/null 2>&1; then
	emerge --ask=n app-admin/eselect
fi
if command -v eselect >/dev/null 2>&1; then
	eselect profile set '${GENTOO_PROFILE}' || true
fi
emerge --sync
emerge --ask=n -uDN @world
printf '%s\n' '${TIMEZONE}' > /etc/timezone
emerge --config sys-libs/timezone-data
printf '%s\n' '${LOCALE}' > /etc/locale.gen
locale-gen
printf 'LANG=%s\n' '${LANG_NAME}' > /etc/env.d/02locale
env-update
set +u
source /etc/profile
set -u
printf 'hostname=%s\n' '${HOSTNAME}' > /etc/conf.d/hostname
"

log "Enabling baseline services"
run_in_chroot "
set -euo pipefail
systemctl enable systemd-networkd systemd-resolved
"

stage_end stage3
