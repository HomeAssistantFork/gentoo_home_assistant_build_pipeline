#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage6
require_root

KERNEL_COMPAT_LABEL="${KERNEL_COMPAT_LABEL:-compat}"
KERNEL_MODERN_LABEL="${KERNEL_MODERN_LABEL:-modern}"

# Install cross-compile toolchain on build host if targeting ARM
if [[ -n "${CROSS_COMPILE:-}" ]] && command -v apt-get >/dev/null 2>&1; then
  log "Installing ARM cross-compile toolchain for ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}"
  apt-get update -y -q
  if [[ "$ARCH" == "arm64" ]]; then
    apt-get install -y -q gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
  else
    apt-get install -y -q gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
  fi
  apt-get install -y -q qemu-user-static binfmt-support || true
fi

# Set up ccache directory on host (bind-mounted into chroot at /tmp/ccache).
# The directory persists across re-runs via the GitHub Actions cache, giving
# incremental compilation speeds even when kernel source is fully re-checked out.
CCACHE_HOST_DIR="${CCACHE_HOST_DIR:-/tmp/ha-ccache-${PLATFORM:-unknown}}"
mkdir -p "$CCACHE_HOST_DIR" "$TARGET_ROOT/tmp/ccache"
if ! mountpoint -q "$TARGET_ROOT/tmp/ccache" 2>/dev/null; then
  mount --bind "$CCACHE_HOST_DIR" "$TARGET_ROOT/tmp/ccache"
fi

# Platform-specific kernel defconfig
case "${PLATFORM:-x64}" in
  x64)     PLATFORM_DEFCONFIG="defconfig" ;;
  pi3)     PLATFORM_DEFCONFIG="bcm2709_defconfig" ;;
  pi4)     PLATFORM_DEFCONFIG="bcm2711_defconfig" ;;
  pizero2) PLATFORM_DEFCONFIG="bcm2835_defconfig" ;;
  bbb)     PLATFORM_DEFCONFIG="omap2plus_defconfig" ;;
  pbv2)    PLATFORM_DEFCONFIG="defconfig" ;; # AM62x — use generic arm64 defconfig until TI config available
  *)       PLATFORM_DEFCONFIG="defconfig" ;;
esac

CHROOT_ARCH="${ARCH:-x86_64}"
CHROOT_CROSS="${CROSS_COMPILE:-}"

log "Building dual kernel tracks (compat + modern) for PLATFORM=${PLATFORM:-x64} ARCH=$CHROOT_ARCH"

# The chroot script uses per-sub-step checkpoints stored in /var/lib/ha-build-state/
# inside the chroot.  Because this directory lives inside TARGET_ROOT it survives
# the rootfs_pack -> rootfs_unpack cycle, so a timed-out kernel job can be re-run
# and will skip already-completed sub-steps (config, build, install).
chroot_script="$(cat <<EOF
set -euo pipefail
set +u
source /etc/profile
set -u

export ARCH="${CHROOT_ARCH}"
export CROSS_COMPILE="${CHROOT_CROSS}"

# ── ccache setup (best-effort) ──────────────────────────────────────────────
if command -v ccache >/dev/null 2>&1; then
  export CCACHE_DIR=/tmp/ccache
  export CC="ccache \${CROSS_COMPILE}gcc"
  echo "ccache enabled (CCACHE_DIR=\$CCACHE_DIR)"
else
  emerge --ask=n --noreplace dev-util/ccache 2>/dev/null && {
    export CCACHE_DIR=/tmp/ccache
    export CC="ccache \${CROSS_COMPILE}gcc"
    echo "ccache installed and enabled"
  } || echo "ccache unavailable; building without it"
fi

# ── Resumable sub-step checkpoint helpers ───────────────────────────────────
CKPT_DIR="/var/lib/ha-build-state"
mkdir -p "\$CKPT_DIR"
is_ckpt()   { [[ -f "\$CKPT_DIR/\$1" ]]; }
mark_ckpt() { date -u +%Y-%m-%dT%H:%M:%SZ > "\$CKPT_DIR/\$1"; echo "  checkpoint: \$1"; }

# ── Kernel sources ───────────────────────────────────────────────────────────
if ! is_ckpt stage6_sources; then
  emerge --ask=n --noreplace sys-kernel/gentoo-sources sys-kernel/installkernel
  mark_ckpt stage6_sources
fi

kernel_src_dir="\$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n1)"
[[ -n "\$kernel_src_dir" ]] || { echo 'No installed kernel sources found' >&2; exit 1; }
ln -sfn "\$kernel_src_dir" /usr/src/linux
cd /usr/src/linux

# ── Shared kernel option helper ──────────────────────────────────────────────
apply_ha_kernel_options() {
  # Overlay filesystem (containers, add-on layers)
  ./scripts/config --module CONFIG_OVERLAY_FS
  # Virtual ethernet pairs (container networking)
  ./scripts/config --module CONFIG_VETH
  # Bridge and bridge-netfilter (Docker default network)
  ./scripts/config --module CONFIG_BRIDGE
  ./scripts/config --module CONFIG_BRIDGE_NETFILTER
  # Dummy and MACVLAN/IPVLAN (Supervisor network isolation)
  ./scripts/config --module CONFIG_DUMMY
  ./scripts/config --module CONFIG_MACVLAN
  ./scripts/config --module CONFIG_IPVLAN
  # Netfilter conntrack and NAT
  ./scripts/config --module CONFIG_NF_CONNTRACK
  ./scripts/config --module CONFIG_NF_NAT
  ./scripts/config --module CONFIG_NF_NAT_TFTP
  ./scripts/config --module CONFIG_NF_CONNTRACK_TFTP
  ./scripts/config --module CONFIG_IP_NF_FILTER
  ./scripts/config --module CONFIG_IP_NF_TARGET_MASQUERADE
  ./scripts/config --module CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
  ./scripts/config --module CONFIG_NETFILTER_XT_MATCH_CONNTRACK
  # Namespaces
  ./scripts/config --enable CONFIG_NAMESPACES
  ./scripts/config --enable CONFIG_NET_NS
  ./scripts/config --enable CONFIG_PID_NS
  ./scripts/config --enable CONFIG_IPC_NS
  ./scripts/config --enable CONFIG_UTS_NS
  ./scripts/config --enable CONFIG_USER_NS
  # cgroups v2
  ./scripts/config --enable CONFIG_CGROUPS
  ./scripts/config --enable CONFIG_CGROUP_FREEZER
  ./scripts/config --enable CONFIG_CGROUP_DEVICE
  ./scripts/config --enable CONFIG_CGROUP_CPUACCT
  ./scripts/config --enable CONFIG_CGROUP_SCHED
  ./scripts/config --enable CONFIG_CPUSETS
  ./scripts/config --enable CONFIG_MEMCG
  ./scripts/config --enable CONFIG_CGROUP_NET_PRIO
  ./scripts/config --enable CONFIG_CGROUP_HUGETLB
  # Seccomp (Docker default seccomp profiles)
  ./scripts/config --enable CONFIG_SECCOMP
  ./scripts/config --enable CONFIG_SECCOMP_FILTER
  # POSIX message queues (Supervisor IPC)
  ./scripts/config --enable CONFIG_POSIX_MQUEUE
  # Keys (container image verification)
  ./scripts/config --enable CONFIG_KEYS
  # iptables legacy (hassio-apparmor and Supervisor use iptables rules)
  ./scripts/config --module CONFIG_IP_NF_IPTABLES
  ./scripts/config --module CONFIG_IP_NF_TARGET_REJECT
  # Live ISO / loopback / optical filesystem support
  ./scripts/config --module CONFIG_BLK_DEV_LOOP || true
  ./scripts/config --module CONFIG_SQUASHFS || true
  ./scripts/config --enable CONFIG_SQUASHFS_XATTR || true
  ./scripts/config --enable CONFIG_SQUASHFS_XZ || true
  ./scripts/config --module CONFIG_ISO9660_FS || true
  ./scripts/config --module CONFIG_UDF_FS || true
  # VM platform support for pure VM workflows
  ./scripts/config --module CONFIG_VIRTIO_PCI || true
  ./scripts/config --module CONFIG_VIRTIO_BLK || true
  ./scripts/config --module CONFIG_VIRTIO_NET || true
  ./scripts/config --module CONFIG_VIRTIO_SCSI || true
  ./scripts/config --module CONFIG_HYPERV || true
  ./scripts/config --module CONFIG_HYPERV_UTILS || true
  ./scripts/config --module CONFIG_HYPERV_NET || true
  ./scripts/config --module CONFIG_HYPERV_STORAGE || true
  ./scripts/config --module CONFIG_XEN || true
  ./scripts/config --module CONFIG_XEN_BLKDEV_FRONTEND || true
  ./scripts/config --module CONFIG_XEN_NETDEV_FRONTEND || true
  ./scripts/config --module CONFIG_DRM_VBOXVIDEO || true
  ./scripts/config --module CONFIG_VBOXSF_FS || true
  # LSM / Security framework
  ./scripts/config --enable CONFIG_SECURITY
  ./scripts/config --enable CONFIG_SECURITY_NETWORK
  ./scripts/config --enable CONFIG_SECURITY_PATH
  # AppArmor
  ./scripts/config --enable CONFIG_SECURITY_APPARMOR
  ./scripts/config --enable CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE
  ./scripts/config --set-str CONFIG_LSM "lockdown,yama,apparmor"
  # Audit subsystem (required by AppArmor)
  ./scripts/config --enable CONFIG_AUDIT
  ./scripts/config --enable CONFIG_AUDITSYSCALL
  ./scripts/config --enable CONFIG_AUDIT_WATCH
  ./scripts/config --enable CONFIG_AUDIT_TREE
}

# ── Compat kernel track ──────────────────────────────────────────────────────
if ! is_ckpt stage6_compat_config; then
  make mrproper
  make ${PLATFORM_DEFCONFIG}
  apply_ha_kernel_options
  make olddefconfig
  mark_ckpt stage6_compat_config
fi

if ! is_ckpt stage6_compat_build; then
  make -j\$(nproc) LOCALVERSION="-${KERNEL_COMPAT_LABEL}"
  mark_ckpt stage6_compat_build
fi

if ! is_ckpt stage6_compat_install; then
  make modules_install
  make install
  cp .config /boot/config-${KERNEL_COMPAT_LABEL}
  mark_ckpt stage6_compat_install
fi

# ── Modern kernel track ──────────────────────────────────────────────────────
if ! is_ckpt stage6_modern_config; then
  make mrproper
  cp /boot/config-${KERNEL_COMPAT_LABEL} .config
  make olddefconfig
  mark_ckpt stage6_modern_config
fi

if ! is_ckpt stage6_modern_build; then
  make -j\$(nproc) LOCALVERSION="-${KERNEL_MODERN_LABEL}"
  mark_ckpt stage6_modern_build
fi

if ! is_ckpt stage6_modern_install; then
  make modules_install
  make install
  cp .config /boot/config-${KERNEL_MODERN_LABEL}
  mark_ckpt stage6_modern_install
fi

echo "Dual kernel build complete."
EOF
)"

run_in_chroot "$chroot_script"

# Unmount ccache bind-mount before leaving stage6
umount "$TARGET_ROOT/tmp/ccache" 2>/dev/null || true

stage_end stage6
