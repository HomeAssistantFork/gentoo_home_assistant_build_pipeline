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

# Shared helper: apply all Docker/Supervisor required kernel options.
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
}

# Compatibility track: conservative defaults for containerized Supervisor workload.
make mrproper
make defconfig
apply_ha_kernel_options
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