EAPI=8

DESCRIPTION="GentooHA dual-track kernel package for Supervisor hosts"
HOMEPAGE="https://github.com/tamus/home_assistant_1"
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64"
IUSE=""

RDEPEND="
	>=sys-kernel/gentooha-kernel-config-alpha-1.0
	sys-kernel/gentoo-sources
	sys-kernel/installkernel
"
DEPEND="${RDEPEND}"

S="${WORKDIR}/linux"

gentooha_platform() {
	if [[ -n "${GENTOOHA_PLATFORM:-}" ]]; then
		echo "${GENTOOHA_PLATFORM}"
		return
	fi

	case "${GENTOOHA_KERNEL_ARCH:-}" in
		x86_64) echo "x64" ;;
		*) die "GENTOOHA_PLATFORM is required for non-x64 kernel builds" ;;
	esac
}

gentooha_kernel_arch() {
	if [[ -n "${GENTOOHA_KERNEL_ARCH:-}" ]]; then
		case "${GENTOOHA_KERNEL_ARCH}" in
			amd64|x86_64) echo "x86" ;;
			*) echo "${GENTOOHA_KERNEL_ARCH}" ;;
		esac
		return
	fi

	case "$(gentooha_platform)" in
		x64) echo "x86" ;;
		pi3|bbb) echo "arm" ;;
		pi4|pizero2|pbv2) echo "arm64" ;;
		*) die "Unsupported GENTOOHA_PLATFORM: $(gentooha_platform)" ;;
	esac
}

gentooha_cross_compile() {
	if [[ -n "${GENTOOHA_CROSS_COMPILE:-}" ]]; then
		echo "${GENTOOHA_CROSS_COMPILE}"
		return
	fi

	case "$(gentooha_platform)" in
		x64) echo "" ;;
		pi3|bbb) echo "arm-linux-gnueabihf-" ;;
		pi4|pizero2|pbv2) echo "aarch64-linux-gnu-" ;;
		*) die "Unsupported GENTOOHA_PLATFORM: $(gentooha_platform)" ;;
	esac
}

gentooha_defconfig() {
	case "$(gentooha_platform)" in
		x64) echo "defconfig" ;;
		pi3) echo "bcm2709_defconfig" ;;
		pi4) echo "bcm2711_defconfig" ;;
		pizero2) echo "bcm2835_defconfig" ;;
		bbb) echo "omap2plus_defconfig" ;;
		pbv2) echo "defconfig" ;;
		*) die "No kernel defconfig for platform $(gentooha_platform)" ;;
	esac
}

gentooha_kernel_image() {
	case "$(gentooha_kernel_arch)" in
		x86) echo "arch/x86/boot/bzImage" ;;
		arm) echo "arch/arm/boot/zImage" ;;
		arm64) echo "arch/arm64/boot/Image" ;;
		*) die "No kernel image path for arch $(gentooha_kernel_arch)" ;;
	esac
}

apply_ha_kernel_options() {
	local flag_file="/usr/share/gentooha-kernel-config-alpha/required-flags.conf"

	if [[ -f "${flag_file}" ]]; then
		while IFS= read -r config_line; do
			config_line="${config_line#${config_line%%[![:space:]]*}}"
			[[ -z "${config_line}" || "${config_line:0:1}" == "#" ]] && continue
			# shellcheck disable=SC2086
			./scripts/config ${config_line} || die "Failed to apply ${config_line}"
		done < <(tr -d '\r' < "${flag_file}")
		return
	fi

	./scripts/config --enable CONFIG_OVERLAY_FS
	./scripts/config --enable CONFIG_DUMMY
	./scripts/config --module CONFIG_MACVLAN
	./scripts/config --module CONFIG_IPVLAN
	./scripts/config --enable CONFIG_NETFILTER
	./scripts/config --enable CONFIG_NETFILTER_ADVANCED
	./scripts/config --enable CONFIG_NF_CONNTRACK
	./scripts/config --enable CONFIG_NF_NAT
	./scripts/config --enable CONFIG_NF_NAT_TFTP
	./scripts/config --enable CONFIG_NF_CONNTRACK_TFTP
	./scripts/config --enable CONFIG_IP_NF_IPTABLES
	./scripts/config --enable CONFIG_IP_NF_FILTER
	./scripts/config --enable CONFIG_IP_NF_TARGET_MASQUERADE
	./scripts/config --enable CONFIG_IP_NF_TARGET_REJECT
	./scripts/config --enable CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
	./scripts/config --enable CONFIG_NETFILTER_XT_MATCH_CONNTRACK
	./scripts/config --enable CONFIG_NETFILTER_XT_TARGET_MASQUERADE
	./scripts/config --enable CONFIG_NF_TABLES
	./scripts/config --enable CONFIG_NFT_NAT
	./scripts/config --enable CONFIG_NFT_MASQ
	./scripts/config --enable CONFIG_BRIDGE
	./scripts/config --enable CONFIG_BRIDGE_NETFILTER
	./scripts/config --enable CONFIG_VETH
	./scripts/config --enable CONFIG_NAMESPACES
	./scripts/config --enable CONFIG_NET_NS
	./scripts/config --enable CONFIG_PID_NS
	./scripts/config --enable CONFIG_IPC_NS
	./scripts/config --enable CONFIG_UTS_NS
	./scripts/config --enable CONFIG_USER_NS
	./scripts/config --enable CONFIG_CGROUPS
	./scripts/config --enable CONFIG_CGROUP_FREEZER
	./scripts/config --enable CONFIG_CGROUP_DEVICE
	./scripts/config --enable CONFIG_CGROUP_CPUACCT
	./scripts/config --enable CONFIG_CGROUP_SCHED
	./scripts/config --enable CONFIG_CPUSETS
	./scripts/config --enable CONFIG_MEMCG
	./scripts/config --enable CONFIG_CGROUP_NET_PRIO
	./scripts/config --enable CONFIG_CGROUP_HUGETLB
	./scripts/config --enable CONFIG_BPF
	./scripts/config --enable CONFIG_BPF_SYSCALL
	./scripts/config --enable CONFIG_CGROUP_BPF
	./scripts/config --enable CONFIG_SECCOMP
	./scripts/config --enable CONFIG_SECCOMP_FILTER
	./scripts/config --enable CONFIG_POSIX_MQUEUE
	./scripts/config --enable CONFIG_KEYS
	./scripts/config --module CONFIG_BLK_DEV_LOOP || true
	./scripts/config --module CONFIG_SQUASHFS || true
	./scripts/config --enable CONFIG_SQUASHFS_XATTR || true
	./scripts/config --enable CONFIG_SQUASHFS_XZ || true
	./scripts/config --module CONFIG_ISO9660_FS || true
	./scripts/config --module CONFIG_UDF_FS || true
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
	./scripts/config --enable CONFIG_SECURITY
	./scripts/config --enable CONFIG_SECURITY_NETWORK
	./scripts/config --enable CONFIG_SECURITY_PATH
	./scripts/config --enable CONFIG_SECURITY_APPARMOR
	./scripts/config --enable CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE
	./scripts/config --set-str CONFIG_LSM "lockdown,yama,apparmor"
	./scripts/config --enable CONFIG_AUDIT
	./scripts/config --enable CONFIG_AUDITSYSCALL
	./scripts/config --enable CONFIG_AUDIT_WATCH
	./scripts/config --enable CONFIG_AUDIT_TREE
}

verify_ha_kernel_options() {
	local cfg="$1"
	local -a required=(
		CONFIG_NETFILTER
		CONFIG_NF_CONNTRACK
		CONFIG_NF_NAT
		CONFIG_IP_NF_IPTABLES
		CONFIG_BRIDGE
		CONFIG_BRIDGE_NETFILTER
		CONFIG_VETH
		CONFIG_OVERLAY_FS
		CONFIG_BPF
		CONFIG_BPF_SYSCALL
		CONFIG_CGROUP_BPF
	)
	local key

	for key in "${required[@]}"; do
		grep -qE "^${key}=[ym]$" "${cfg}" || die "Missing required kernel option ${key} in ${cfg}"
	done

	grep -qE '^(CONFIG_IP_NF_TARGET_MASQUERADE|CONFIG_NETFILTER_XT_TARGET_MASQUERADE|CONFIG_NFT_MASQ)=[ym]$' "${cfg}" \
		|| die "Missing MASQUERADE support in ${cfg}"
}

stage_track() {
	local label="$1"
	local seed_config="${2:-}"
	local kernel_arch
	local cross_compile
	local image_path
	local kernel_release
	local source_release
	local image_root="${T}/image-root"
	local boot_name

	kernel_arch="$(gentooha_kernel_arch)"
	cross_compile="$(gentooha_cross_compile)"
	image_path="$(gentooha_kernel_image)"

	einfo "Building ${label} kernel track for $(gentooha_platform)"
	emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" mrproper || die
	if [[ -n "${seed_config}" ]]; then
		cp "${seed_config}" .config || die
	else
		emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" "$(gentooha_defconfig)" || die
	fi

	apply_ha_kernel_options
	emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" olddefconfig || die
	apply_ha_kernel_options
	emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" olddefconfig || die
	emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" LOCALVERSION="-${label}" || die
	if [[ "${kernel_arch}" != "x86" ]]; then
		emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" LOCALVERSION="-${label}" dtbs || die
	fi

	kernel_release="$(make -s ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" LOCALVERSION="-${label}" kernelrelease)"
	[[ -n "${kernel_release}" ]] || die "Unable to determine kernel release for ${label}"

	emake ARCH="${kernel_arch}" CROSS_COMPILE="${cross_compile}" LOCALVERSION="-${label}" \
		INSTALL_MOD_PATH="${image_root}" DEPMOD=/bin/true modules_install || die

	[[ -f "${image_path}" ]] || die "Kernel image not found at ${image_path}"
	install -Dm0644 "${image_path}" "${image_root}/boot/vmlinuz-${kernel_release}" || die
	install -Dm0644 .config "${image_root}/boot/config-${label}" || die
	if [[ -f System.map ]]; then
		install -Dm0644 System.map "${image_root}/boot/System.map-${kernel_release}" || die
	fi

	if [[ "${kernel_arch}" != "x86" && -d arch/${kernel_arch}/boot/dts ]]; then
		while IFS= read -r -d '' dtb; do
			boot_name="${dtb##*/}"
			install -Dm0644 "${dtb}" "${image_root}/boot/${boot_name}" || die
		done < <(find "arch/${kernel_arch}/boot/dts" -type f -name '*.dtb' -print0)
	fi

	source_release="${kernel_release%-${label}}"
	if [[ -d "${image_root}/lib/modules/${kernel_release}" ]]; then
		ln -snf "/usr/src/linux-${source_release}" "${image_root}/lib/modules/${kernel_release}/build" || die
		ln -snf "/usr/src/linux-${source_release}" "${image_root}/lib/modules/${kernel_release}/source" || die
	fi

	verify_ha_kernel_options .config
	cp .config "${T}/config-${label}" || die
}

src_unpack() {
	local kernel_src_dir

	kernel_src_dir="$(find /usr/src -maxdepth 1 -mindepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
	[[ -n "${kernel_src_dir}" ]] || die "No installed kernel sources found under /usr/src"

	mkdir -p "${S}" || die
	cp -a "${kernel_src_dir}/." "${S}/" || die
}

src_compile() {
	local compat_label="${GENTOOHA_KERNEL_COMPAT_LABEL:-compat}"
	local modern_label="${GENTOOHA_KERNEL_MODERN_LABEL:-modern}"

	stage_track "${compat_label}"
	stage_track "${modern_label}" "${T}/config-${compat_label}"
}

src_install() {
	cp -a "${T}/image-root/." "${D}/" || die
}

pkg_postinst() {
	local compat_label="${GENTOOHA_KERNEL_COMPAT_LABEL:-compat}"
	local modern_label="${GENTOOHA_KERNEL_MODERN_LABEL:-modern}"
	local source_dir=""
	local kernel_config=""
	local module_dir
	local kernel_release

	source_dir="$(find /usr/src -maxdepth 1 -mindepth 1 -type d -name 'linux-*' | sort -V | tail -n 1)"
	if [[ -n "${source_dir}" ]]; then
		ln -sfn "${source_dir}" /usr/src/linux || die "Unable to refresh /usr/src/linux symlink"
		if [[ -f "/boot/config-${modern_label}" ]]; then
			kernel_config="/boot/config-${modern_label}"
		elif [[ -f "/boot/config-${compat_label}" ]]; then
			kernel_config="/boot/config-${compat_label}"
		fi
		if [[ -n "${kernel_config}" ]]; then
			cp -f "${kernel_config}" "${source_dir}/.config" || die "Unable to refresh ${source_dir}/.config"
		fi
	fi

	for module_dir in /lib/modules/*; do
		[[ -d "${module_dir}" ]] || continue
		kernel_release="${module_dir##*/}"
		if [[ ! -f "${module_dir}/modules.dep" ]]; then
			depmod -a "${kernel_release}" || die "Unable to generate module metadata for ${kernel_release}"
		fi
	done

	elog "GentooHA kernel tracks installed."
	elog "Compatibility config: /boot/config-${compat_label}"
	elog "Modern config: /boot/config-${modern_label}"
	if [[ -n "${source_dir}" ]]; then
		elog "Configured kernel sources: ${source_dir}"
	fi
}