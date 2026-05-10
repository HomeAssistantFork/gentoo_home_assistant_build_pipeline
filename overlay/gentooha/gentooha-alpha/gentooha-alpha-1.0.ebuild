EAPI=8

DESCRIPTION="GentooHA alpha meta-package — installs the full Home Assistant Supervisor stack on Gentoo"
HOMEPAGE="https://github.com/HomeAssistantFork/home-assistant-1"
LICENSE="metapackage"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64"
IUSE=""

# This is a pure meta-package; all work is done by dependencies.
S="${WORKDIR}"

RDEPEND="
	>=sys-kernel/gentooha-kernel-config-alpha-1.0

	sys-apps/gentooha-compat
	=sys-apps/gentooha-supervisor-9999
	=sys-apps/gentooha-os-agent-9999

	app-containers/docker
	net-firewall/iptables

	sys-apps/apparmor
	sys-apps/apparmor-utils

	net-misc/openssh

	sys-boot/grub

	app-misc/jq
	net-misc/curl
	dev-vcs/git
	dev-lang/go
"
DEPEND="${RDEPEND}"

src_install() {
	# No files to install — this is a pure dependency aggregate.
	:
}
