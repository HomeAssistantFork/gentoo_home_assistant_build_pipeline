#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage6
require_root

KERNEL_COMPAT_LABEL="${KERNEL_COMPAT_LABEL:-compat}"
KERNEL_MODERN_LABEL="${KERNEL_MODERN_LABEL:-modern}"

log "Building dual kernel tracks (compat + modern)"
run_in_chroot "
set -euo pipefail
source /etc/profile

emerge --ask=n --noreplace sys-kernel/gentoo-sources sys-kernel/genkernel sys-kernel/installkernel

cd /usr/src/linux
make mrproper

# Compatibility track: conservative defaults for containerized Supervisor workload.
make defconfig
yes '' | make oldconfig
make -j"$(nproc)"
make modules_install
make install
cp .config /boot/config-${KERNEL_COMPAT_LABEL}

# Modern track: rebuild after refresh; tune this config for latest features.
make mrproper
cp /boot/config-${KERNEL_COMPAT_LABEL} .config
yes '' | make oldconfig
make -j"$(nproc)"
make modules_install
make install
cp .config /boot/config-${KERNEL_MODERN_LABEL}
"

stage_end stage6
