EAPI=8

DESCRIPTION="GentooHA os-agent — Home Assistant OS Agent built from source"
HOMEPAGE="https://github.com/HomeAssistantFork/os-agent https://github.com/home-assistant/os-agent"
LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS=""
IUSE=""

inherit git-r3 go-module systemd

# Try the GentooHA fork org first; fall back to upstream home-assistant.
EGIT_REPO_URI="
	https://github.com/HomeAssistantFork/os-agent
	https://github.com/home-assistant/os-agent
"

BDEPEND="
	dev-lang/go
"
RDEPEND="
	sys-apps/dbus
"
DEPEND="${RDEPEND}"

PROPERTIES="live"
RESTRICT="mirror network-sandbox"

src_unpack() {
	# Clone the repository first, then vendor the Go module dependencies.
	git-r3_src_unpack
	go-module_live_vendor
}

src_compile() {
	# os-agent is a Go project; build the binary in the repo root.
	ego build -o os-agent .
}

src_install() {
	dobin os-agent

	# Install the systemd service unit (path varies between repo versions).
	local svc
	for svc in \
		"${S}/deployment/os-agent.service" \
		"${S}/os-agent.service" \
		"${S}/data/os-agent.service"; do
		if [[ -f "${svc}" ]]; then
			systemd_dounit "${svc}"
			return
		fi
	done

	# Fallback: generate a minimal service unit if none found in the repo.
	ewarn "os-agent.service not found in repo; generating minimal unit."
	systemd_newunit - os-agent.service <<-'EOF'
		[Unit]
		Description=Home Assistant OS Agent
		Documentation=https://github.com/home-assistant/os-agent
		After=dbus.service
		Requires=dbus.service

		[Service]
		Type=dbus
		BusName=io.hass.os
		ExecStart=/usr/bin/os-agent
		Restart=on-failure
		RestartSec=5s

		[Install]
		WantedBy=multi-user.target
	EOF
}

pkg_postinst() {
	elog "gentooha-os-agent installed."
	elog "Enable the service: systemctl enable --now os-agent.service"
}
