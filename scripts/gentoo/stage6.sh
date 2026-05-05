#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage6
require_root
mount_chroot_fs

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

# Platform-specific kernel defconfig
case "${PLATFORM:-x64}" in
  x64)    PLATFORM_DEFCONFIG="defconfig" ;;
  pi3)    PLATFORM_DEFCONFIG="bcm2709_defconfig" ;;
  pi4)    PLATFORM_DEFCONFIG="bcm2711_defconfig" ;;
  pizero2) PLATFORM_DEFCONFIG="bcm2835_defconfig" ;;
  bbb)    PLATFORM_DEFCONFIG="omap2plus_defconfig" ;;
  pbv2)   PLATFORM_DEFCONFIG="defconfig" ;; # AM62x — use generic arm64 defconfig until TI config available
  *)      PLATFORM_DEFCONFIG="defconfig" ;;
esac

# Pass ARCH/CROSS_COMPILE into chroot environment
CHROOT_ARCH="${ARCH:-x86_64}"
CHROOT_CROSS="${CROSS_COMPILE:-}"

log "Building dual kernel tracks (compat + modern) for PLATFORM=${PLATFORM:-x64} ARCH=$CHROOT_ARCH"
chroot_script="$(cat <<EOF
set -euo pipefail
set +u
source /etc/profile
set -u

export ARCH="${CHROOT_ARCH}"
export CROSS_COMPILE="${CHROOT_CROSS}"

emerge --ask=n --noreplace sys-kernel/gentoo-sources sys-kernel/installkernel

kernel_src_dir="\$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
[[ -n "\$kernel_src_dir" ]] || { echo 'No installed kernel sources found' >&2; exit 1; }
ln -sfn "\$kernel_src_dir" /usr/src/linux
cd /usr/src/linux

# Shared helper: apply all Docker/Supervisor required kernel options.
apply_ha_kernel_options() {
  # Overlay filesystem (containers, add-on layers) — built-in
  ./scripts/config --enable CONFIG_OVERLAY_FS
  # Dummy and MACVLAN/IPVLAN (Supervisor network isolation)
  ./scripts/config --enable CONFIG_DUMMY
  ./scripts/config --module CONFIG_MACVLAN
  ./scripts/config --module CONFIG_IPVLAN
  # Netfilter core — built-in so Docker never needs modprobe
  ./scripts/config --enable CONFIG_NETFILTER
  ./scripts/config --enable CONFIG_NETFILTER_ADVANCED
  ./scripts/config --enable CONFIG_NF_CONNTRACK
  ./scripts/config --enable CONFIG_NF_NAT
  ./scripts/config --enable CONFIG_NF_NAT_TFTP
  ./scripts/config --enable CONFIG_NF_CONNTRACK_TFTP
  ./scripts/config --enable CONFIG_IP_NF_IPTABLES
  ./scripts/config --enable CONFIG_IP_NF_FILTER
  ./scripts/config --enable CONFIG_IP_NF_NAT
  ./scripts/config --enable CONFIG_IP_NF_TARGET_MASQUERADE
  ./scripts/config --enable CONFIG_IP_NF_TARGET_REJECT
  ./scripts/config --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
  ./scripts/config --enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK
  ./scripts/config --enable CONFIG_NETFILTER_XT_TARGET_MASQUERADE
  ./scripts/config --enable CONFIG_NF_TABLES
  ./scripts/config --enable CONFIG_NFT_NAT
  ./scripts/config --enable CONFIG_NFT_MASQ
  # Bridge and veth — built-in for Docker bridged networking
  ./scripts/config --enable CONFIG_BRIDGE
  ./scripts/config --enable CONFIG_BRIDGE_NETFILTER
  ./scripts/config --enable CONFIG_VETH
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
  # iptables legacy (already enabled as built-in above via CONFIG_IP_NF_IPTABLES)
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

verify_ha_kernel_options() {
  local cfg="\$1"
  local -a required=(
    CONFIG_NETFILTER
    CONFIG_NF_CONNTRACK
    CONFIG_NF_NAT
    CONFIG_IP_NF_IPTABLES
    CONFIG_IP_NF_NAT
    CONFIG_IP_NF_TARGET_MASQUERADE
    CONFIG_BRIDGE
    CONFIG_BRIDGE_NETFILTER
    CONFIG_VETH
    CONFIG_OVERLAY_FS
  )

  for key in "\${required[@]}"; do
    grep -qE "^\${key}=[ym]$" "\$cfg" || {
      echo "Missing required kernel option in \$cfg: \${key} (need =y or =m)" >&2
      exit 1
    }
  done
}

# Compatibility track: conservative defaults for containerized Supervisor workload.
make mrproper
make ${PLATFORM_DEFCONFIG}
apply_ha_kernel_options
make olddefconfig
# Re-apply critical built-in options that olddefconfig may have reverted to =m
apply_ha_kernel_options
make olddefconfig
make -j\$(nproc) LOCALVERSION="-${KERNEL_COMPAT_LABEL}"
make modules_install
make install
cp .config /boot/config-${KERNEL_COMPAT_LABEL}
verify_ha_kernel_options /boot/config-${KERNEL_COMPAT_LABEL}

# Modern track: start from the compatibility config but keep a distinct kernel label.
make mrproper
cp /boot/config-${KERNEL_COMPAT_LABEL} .config
apply_ha_kernel_options
make olddefconfig
make -j\$(nproc) LOCALVERSION="-${KERNEL_MODERN_LABEL}"
make modules_install
make install
cp .config /boot/config-${KERNEL_MODERN_LABEL}
verify_ha_kernel_options /boot/config-${KERNEL_MODERN_LABEL}
EOF
)"

run_in_chroot "$chroot_script"

stage_end stage6