EAPI=8

inherit systemd

DESCRIPTION="GentooHA host compatibility layer for Home Assistant Supervisor"
HOMEPAGE="https://github.com/HomeAssistantFork/home-assistant-1"
LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64"
IUSE=""

RDEPEND="
	app-containers/docker
	sys-apps/systemd
"
DEPEND="${RDEPEND}"

# All content is generated/installed by this ebuild — no sources to fetch.
S="${WORKDIR}"

src_install() {
	# ── Compatibility os-release ──────────────────────────────────────────────
	insinto /etc/ha-compat
	newins - os-release <<-'EOF'
		NAME=Home Assistant OS Compatibility Layer
		ID=homeassistant
		VERSION=Gentoo-Compatible
		VERSION_ID=rolling
		PRETTY_NAME=Home Assistant Compatible Gentoo Host
		CPE_NAME=cpe:/o:home-assistant:home-assistant-os:compat
		HOME_URL=https://www.home-assistant.io/
		SUPERVISOR=1
	EOF

	# ── Helper scripts ────────────────────────────────────────────────────────
	exeinto /usr/local/bin
	doexe "${FILESDIR}/ha-host-info"
	doexe "${FILESDIR}/ha-os-release-sync"

	# ── systemd unit ─────────────────────────────────────────────────────────
	systemd_dounit "${FILESDIR}/ha-os-release-sync.service"

	# ── Docker daemon configuration ───────────────────────────────────────────
	insinto /etc/docker
	newins "${FILESDIR}/docker-daemon.json" daemon.json

	# ── Supervisor required runtime directories ───────────────────────────────
	keepdir /mnt/data
	keepdir /run/supervisor

	# ── kernel.dmesg_restrict sysctl (Supervisor reads dmesg) ─────────────────
	insinto /etc/sysctl.d
	newins - 80-hassio.conf <<-'EOF'
		kernel.dmesg_restrict=0
	EOF
}

pkg_postinst() {
	elog "GentooHA compat layer installed."
	elog "Enable the sync service: systemctl enable --now ha-os-release-sync.service"
}
