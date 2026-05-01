#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage6
require_root

KERNEL_COMPAT_LABEL="${KERNEL_COMPAT_LABEL:-compat}"
KERNEL_MODERN_LABEL="${KERNEL_MODERN_LABEL:-modern}"

log "Building dual kernel tracks (compat + modern)"
chroot_script="$(cat <<EOF
set -euo pipefail
set +u
source /etc/profile
set -u

emerge --ask=n --noreplace sys-kernel/gentoo-sources sys-kernel/installkernel

kernel_src_dir="\$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
[[ -n "\$kernel_src_dir" ]] || { echo 'No installed kernel sources found' >&2; exit 1; }
ln -sfn "\$kernel_src_dir" /usr/src/linux
cd /usr/src/linux

# Compatibility track: conservative defaults for containerized Supervisor workload.
make mrproper
make defconfig
make olddefconfig
make -j\$(nproc) LOCALVERSION="-${KERNEL_COMPAT_LABEL}"
make modules_install
make install
cp .config /boot/config-${KERNEL_COMPAT_LABEL}

# Modern track: start from the compatibility config but keep a distinct kernel label.
make mrproper
cp /boot/config-${KERNEL_COMPAT_LABEL} .config
make olddefconfig
make -j\$(nproc) LOCALVERSION="-${KERNEL_MODERN_LABEL}"
make modules_install
make install
cp .config /boot/config-${KERNEL_MODERN_LABEL}
EOF
)"

run_in_chroot "$chroot_script"

stage_end stage6