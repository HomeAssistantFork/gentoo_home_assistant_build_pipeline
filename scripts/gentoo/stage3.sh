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

log "Configuring portage and system profile inside chroot"
run_in_chroot "
set -euo pipefail
source /etc/profile
emerge-webrsync
eselect profile set '${GENTOO_PROFILE}'
emerge --sync
emerge --ask=n -uDN @world
printf '%s\n' '${TIMEZONE}' > /etc/timezone
emerge --config sys-libs/timezone-data
printf '%s\n' '${LOCALE}' > /etc/locale.gen
locale-gen
locale_target="$(eselect locale list | awk '/en_US\.utf8/{gsub(/[[\]*]/,"",$1); print $1; exit}')"
if [[ -n "$locale_target" ]]; then
	eselect locale set "$locale_target"
fi
printf 'LANG=en_US.UTF-8\n' > /etc/env.d/02locale
env-update && source /etc/profile
printf 'hostname=${HOSTNAME}\n' > /etc/conf.d/hostname
"

log "Enabling baseline services"
run_in_chroot "
set -euo pipefail
systemctl enable systemd-networkd systemd-resolved
"

stage_end stage3
