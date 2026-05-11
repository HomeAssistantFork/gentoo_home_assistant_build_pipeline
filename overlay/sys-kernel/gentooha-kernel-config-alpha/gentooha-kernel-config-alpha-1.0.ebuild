EAPI=8

DESCRIPTION="GentooHA alpha kernel config package"
HOMEPAGE="https://github.com/tamus/home_assistant_1"
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64"
IUSE=""

S="${WORKDIR}"

RDEPEND="
	sys-apps/systemd
	app-containers/docker
	net-firewall/iptables
	app-misc/jq
	net-misc/curl
	dev-vcs/git
"
DEPEND="${RDEPEND}"

src_install() {
	insinto /usr/share/gentooha-kernel-config-alpha
	doins "${FILESDIR}/required-flags.conf"
}
