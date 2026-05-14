#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage6
require_root
mount_chroot_fs
ensure_portage_cache_dirs

KERNEL_COMPAT_LABEL="${KERNEL_COMPAT_LABEL:-compat}"
KERNEL_MODERN_LABEL="${KERNEL_MODERN_LABEL:-modern}"
BUILD_UML_KERNEL="${BUILD_UML_KERNEL:-false}"

# Pass ARCH/CROSS_COMPILE into chroot environment
CHROOT_ARCH="${ARCH:-x86_64}"
CHROOT_CROSS="${CROSS_COMPILE:-}"

log "Building Portage-managed kernel package for PLATFORM=${PLATFORM:-x64} ARCH=$CHROOT_ARCH"
chroot_script="$(cat <<EOF
set -euo pipefail
set +u
source /etc/profile
set -u

mkdir -p /etc/portage/package.accept_keywords /etc/portage/env /etc/portage/package.env
if ! grep -qxF 'sys-kernel/gentooha-kernel-config-alpha **' /etc/portage/package.accept_keywords/gentooha 2>/dev/null; then
  echo 'sys-kernel/gentooha-kernel-config-alpha **' >> /etc/portage/package.accept_keywords/gentooha
fi
if ! grep -qxF 'sys-kernel/gentooha-kernel-alpha **' /etc/portage/package.accept_keywords/gentooha 2>/dev/null; then
  echo 'sys-kernel/gentooha-kernel-alpha **' >> /etc/portage/package.accept_keywords/gentooha
fi

cat > /etc/portage/env/gentooha-kernel-alpha <<KERNELENV
GENTOOHA_PLATFORM="${PLATFORM}"
GENTOOHA_KERNEL_ARCH="${CHROOT_ARCH}"
GENTOOHA_CROSS_COMPILE="${CHROOT_CROSS}"
GENTOOHA_KERNEL_COMPAT_LABEL="${KERNEL_COMPAT_LABEL}"
GENTOOHA_KERNEL_MODERN_LABEL="${KERNEL_MODERN_LABEL}"
KERNELENV

cat > /etc/portage/package.env/gentooha-kernel-alpha <<'PACKAGEENV'
sys-kernel/gentooha-kernel-alpha gentooha-kernel-alpha
PACKAGEENV

EMERGE_DEFAULT_OPTS="" emerge --ask=n --buildpkg=y sys-kernel/gentooha-kernel-alpha

latest_kernel="\$(find /boot -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'kernel-*' \) | sort -V | tail -n 1)"
[[ -n "\$latest_kernel" ]] || { echo 'No installed kernel image found in /boot after emerge' >&2; exit 1; }
[[ -f "/boot/config-${KERNEL_COMPAT_LABEL}" ]] || { echo 'Missing compatibility kernel config in /boot' >&2; exit 1; }
[[ -f "/boot/config-${KERNEL_MODERN_LABEL}" ]] || { echo 'Missing modern kernel config in /boot' >&2; exit 1; }

if [[ "${BUILD_UML_KERNEL}" == "true" && "${CHROOT_ARCH}" == "x86_64" ]]; then
  kernel_src_dir="\$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
  [[ -n "\$kernel_src_dir" ]] || { echo 'No installed kernel sources found for UML build' >&2; exit 1; }
  cd "\$kernel_src_dir"
  echo "Building optional User-Mode Linux kernel track"
  make mrproper
  make ARCH=um defconfig
  make ARCH=um olddefconfig
  make -j\$(nproc) ARCH=um linux
  cp linux /boot/linux-uml
  cp .config /boot/config-uml
fi
EOF
)"

run_in_chroot "$chroot_script"

stage_end stage6
