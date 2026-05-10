EAPI=8

DESCRIPTION="GentooHA Supervisor launcher — scripts and units from supervised-installer"
HOMEPAGE="https://github.com/HomeAssistantFork/supervised-installer https://github.com/home-assistant/supervised-installer"
LICENSE="Apache-2.0"
SLOT="0"
# No stable keywords for a live ebuild
KEYWORDS=""
IUSE=""

inherit git-r3 systemd

# Try the GentooHA fork org first; fall back to upstream home-assistant.
# git-r3 will attempt each URI in order and use the first that works.
EGIT_REPO_URI="
	https://github.com/HomeAssistantFork/supervised-installer
	https://github.com/home-assistant/supervised-installer
"

RDEPEND="
	app-containers/docker
	sys-apps/gentooha-compat
	app-misc/jq
	net-misc/curl
"
DEPEND="${RDEPEND}"

PROPERTIES="live"
RESTRICT="mirror"

src_install() {
	# supervised-installer stores its rootfs files under rootfs/
	local rootfs="${S}/rootfs"
	if [[ ! -d "${rootfs}" ]]; then
		eerror "Expected rootfs/ directory not found in supervised-installer checkout."
		eerror "Repo structure may have changed. Check ${S}."
		die "rootfs/ not found"
	fi

	# ── Supervisor launch script ───────────────────────────────────────────────
	if [[ -f "${rootfs}/usr/sbin/hassio-supervisor" ]]; then
		exeinto /usr/sbin
		doexe "${rootfs}/usr/sbin/hassio-supervisor"

		# Patch: replace AppArmor named profile with unconfined so the script
		# works on Gentoo hosts that don't ship the hassio-supervisor profile.
		sed -i \
			-e 's|--security-opt apparmor="hassio-supervisor"|--security-opt apparmor=unconfined|g' \
			-e 's|--security-opt apparmor=hassio-supervisor|--security-opt apparmor=unconfined|g' \
			"${ED}/usr/sbin/hassio-supervisor"

		# Fill in known placeholder values so the script works after first boot.
		sed -i \
			-e 's|%%HASSIO_CONFIG%%|/etc/hassio.json|g' \
			-e 's|%%BINARY_DOCKER%%|/usr/bin/docker|g' \
			-e 's|%%SERVICE_DOCKER%%|docker.service|g' \
			-e 's|%%BINARY_HASSIO%%|/usr/sbin/hassio-supervisor|g' \
			-e 's|%%HASSIO_APPARMOR_BINARY%%|/usr/sbin/hassio-apparmor|g' \
			"${ED}/usr/sbin/hassio-supervisor"
	fi

	# ── AppArmor helper script ────────────────────────────────────────────────
	if [[ -f "${rootfs}/usr/sbin/hassio-apparmor" ]]; then
		exeinto /usr/sbin
		doexe "${rootfs}/usr/sbin/hassio-apparmor"
		sed -i \
			-e 's|%%HASSIO_CONFIG%%|/etc/hassio.json|g' \
			-e 's|%%BINARY_DOCKER%%|/usr/bin/docker|g' \
			-e 's|%%SERVICE_DOCKER%%|docker.service|g' \
			-e 's|%%HASSIO_APPARMOR_BINARY%%|/usr/sbin/hassio-apparmor|g' \
			"${ED}/usr/sbin/hassio-apparmor" || true
	fi

	# ── CLI tool ──────────────────────────────────────────────────────────────
	if [[ -f "${rootfs}/usr/bin/ha" ]]; then
		exeinto /usr/bin
		doexe "${rootfs}/usr/bin/ha"
	fi

	# ── systemd units ─────────────────────────────────────────────────────────
	local unit
	for unit in \
		hassio-supervisor.service \
		hassio-apparmor.service; do
		local unit_src
		for unit_src in \
			"${rootfs}/etc/systemd/system/${unit}" \
			"${rootfs}/usr/lib/systemd/system/${unit}" \
			"${rootfs}/lib/systemd/system/${unit}"; do
			if [[ -f "${unit_src}" ]]; then
				systemd_dounit "${unit_src}"
				break
			fi
		done
	done

	# ── hassio.json template ──────────────────────────────────────────────────
	# Machine type is arch-specific; stage8 fills in %%MACHINE%% at build time.
	insinto /etc
	newins - hassio.json <<-'EOF'
		{
		    "supervisor": "ghcr.io/home-assistant/amd64-hassio-supervisor",
		    "machine": "%%MACHINE%%",
		    "data": "/var/lib/homeassistant"
		}
	EOF

	# ── Data directory ────────────────────────────────────────────────────────
	keepdir /var/lib/homeassistant
	keepdir /var/lib/homeassistant/apparmor
}

pkg_postinst() {
	elog "gentooha-supervisor installed."
	elog "Before first boot, replace %%MACHINE%% in /etc/hassio.json with the"
	elog "correct machine type (e.g. generic-x86-64, raspberrypi4-64)."
	elog "Enable services:"
	elog "  systemctl enable hassio-apparmor.service hassio-supervisor.service"
}
