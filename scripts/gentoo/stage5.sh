#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

stage_start stage5
require_root
mount_chroot_fs
ensure_portage_cache_dirs

log "Refreshing local gentooha overlay in chroot"
rm -rf "$TARGET_ROOT/var/db/repos/gentooha"
mkdir -p "$TARGET_ROOT/var/db/repos/gentooha"
cp -a "$REPO_ROOT/overlay/." "$TARGET_ROOT/var/db/repos/gentooha/"

log "Installing GentooHA compat layer (sys-apps/gentooha-compat)"
run_in_chroot "$(cat <<'CHROOT_STAGE5'
set -euo pipefail
set +u
source /etc/profile
set -u

export PORTAGE_BACKGROUND=1
export NOCOLOR="true"
export TERM="dumb"

case "${ARCH:-amd64}" in
	x86_64|amd64) PORTAGE_ARCH="amd64" ;;
	arm64|aarch64) PORTAGE_ARCH="arm64" ;;
	arm) PORTAGE_ARCH="arm" ;;
	*) PORTAGE_ARCH="${ARCH:-amd64}" ;;
esac

BINREPO_SYNC_URI='https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64'
case "${PORTAGE_ARCH}" in
	arm)
		BINREPO_SYNC_URI='https://distfiles.gentoo.org/releases/arm/binpackages/23.0/armv7a_hardfp'
		;;
	arm64)
		BINREPO_SYNC_URI='https://distfiles.gentoo.org/releases/arm64/binpackages/23.0/aarch64'
		;;
esac

# Stage artifacts may not retain a populated Gentoo tree or /var/tmp.
mkdir -p /var/tmp /var/db/repos/gentoo /var/db/repos/gentooha /etc/portage/repos.conf
if [[ ! -d /var/db/repos/gentoo/profiles ]]; then
	echo "[stage5] Seeding Gentoo repository metadata"
	emerge-webrsync
fi

cat >/etc/portage/repos.conf/gentooha.conf <<'EOF'
[gentooha]
location = /var/db/repos/gentooha
masters = gentoo
auto-sync = no
EOF

if command -v ebuild >/dev/null 2>&1 && [[ ! -f /var/db/repos/gentooha/sys-apps/gentooha-compat/Manifest ]]; then
	find /var/db/repos/gentooha -mindepth 3 -maxdepth 3 -name '*.ebuild' -print0 | while IFS= read -r -d '' ebuild_file; do
		pkg_dir="$(dirname "$ebuild_file")"
		echo "[stage5] Generating manifest for overlay package: $pkg_dir"
		(cd "$pkg_dir" && ebuild "$(basename "$ebuild_file")" manifest)
	done
fi

if command -v python3 >/dev/null 2>&1; then
	python3 - <<'PY'
import pathlib

targets = sorted(pathlib.Path('/usr/lib').glob('python*/site-packages/portage/util/_pty.py'))
for p in targets:
	txt = p.read_text(encoding='utf-8')
	changed = False

	# 1. Force _disable_openpty = True so Portage skips openpty().
	marker = '_disable_openpty = platform.system() in ("SunOS",)'
	if marker in txt and '_disable_openpty = True' not in txt:
		txt = txt.replace(marker, marker + '\n_disable_openpty = True', 1)
		changed = True
		print(f'[stage5] Set _disable_openpty=True: {p}')
	elif '_disable_openpty = True' not in txt:
		txt = txt.replace(
			'_fbsd_test_pty = platform.system() == "FreeBSD"',
			'_disable_openpty = True\n_fbsd_test_pty = platform.system() == "FreeBSD"',
			1,
		)
		changed = True
		print(f'[stage5] Injected _disable_openpty=True: {p}')
	else:
		print(f'[stage5] _disable_openpty already set: {p}')

	# 2. Override _create_pty_or_pipe so any termios.error falls back to a plain
	#    pipe. Current Portage revisions may not keep a stable function body, so
	#    append a guarded wrapper instead of trying to replace the definition.
	GUARD_MARKER = '# [stage5-qemu-guard]'
	if GUARD_MARKER not in txt:
		txt = txt.rstrip() + (
			'\n\n'
			+ GUARD_MARKER + '\n'
			+ '_create_pty_or_pipe_stage5_orig = _create_pty_or_pipe\n'
			+ 'def _create_pty_or_pipe(*args, **kwargs):\n'
			+ '\timport os as _os\n'
			+ '\timport termios as _termios\n'
			+ '\ttry:\n'
			+ '\t\treturn _create_pty_or_pipe_stage5_orig(*args, **kwargs)\n'
			+ '\texcept _termios.error:\n'
			+ '\t\tr, w = _os.pipe()\n'
			+ '\t\treturn False, r, w\n'
			+ '\n'
		)
		changed = True
		print(f'[stage5] Appended _create_pty_or_pipe pipe fallback: {p}')

	if changed:
		p.write_text(txt, encoding='utf-8')
PY
fi

if [[ -f /etc/portage/make.conf ]]; then
	sed -i -E '/^PORTAGE_BACKGROUND=|^NOCOLOR=|^FEATURES=|^EMERGE_DEFAULT_OPTS=|^PORTAGE_BINHOST=|^PORTAGE_GPG_DIR=/d' /etc/portage/make.conf || true
fi
printf 'PORTAGE_BACKGROUND="1"\n' >> /etc/portage/make.conf
printf 'NOCOLOR="true"\n' >> /etc/portage/make.conf
printf 'FEATURES="getbinpkg -pty"\n' >> /etc/portage/make.conf
printf 'PORTAGE_BINHOST="https://packages.gentoo.org/packages/index.gpkg.tar"\n' >> /etc/portage/make.conf

mkdir -p /etc/portage/binrepos.conf
if [[ -f /etc/portage/binrepos.conf/gentoo.conf ]]; then
	sed -i -E 's|^sync-uri *=.*|sync-uri = '"$BINREPO_SYNC_URI"'|' /etc/portage/binrepos.conf/gentoo.conf
	sed -i -E 's|^location *=.*|location = /var/cache/binhost/gentoo|' /etc/portage/binrepos.conf/gentoo.conf
	sed -i -E 's|^priority *=.*|priority = 1|' /etc/portage/binrepos.conf/gentoo.conf
	if grep -q '^verify-signature' /etc/portage/binrepos.conf/gentoo.conf; then
		sed -i -E 's|^verify-signature *=.*|verify-signature = false|' /etc/portage/binrepos.conf/gentoo.conf
	else
		printf 'verify-signature = false\n' >> /etc/portage/binrepos.conf/gentoo.conf
	fi
else
	cat >/etc/portage/binrepos.conf/gentoo.conf <<EOF
[gentoo]
priority = 1
sync-uri = $BINREPO_SYNC_URI
location = /var/cache/binhost/gentoo
verify-signature = false
EOF
fi
rm -rf /etc/portage/gnupg

mkdir -p /etc/portage/package.accept_keywords
cat >/etc/portage/package.accept_keywords/gentooha <<EOF
app-containers/docker ~${PORTAGE_ARCH}
app-containers/containerd ~${PORTAGE_ARCH}
app-containers/runc ~${PORTAGE_ARCH}
app-emulation/qemu ~${PORTAGE_ARCH}
dev-go/go-md2man ~${PORTAGE_ARCH}
sys-apps/gentooha-compat **
EOF

# gentooha-compat is pulled as a dep of gentooha-alpha in stage4, but emerge
# --noreplace makes this a no-op if already installed so the stage is safe to
# run standalone when skipping stage4.
emerge_args=(--ask=n --getbinpkg --usepkg --binpkg-respect-use=y --noreplace)
if [[ "${ARCH:-amd64}" == arm* || "${ARCH:-amd64}" == aarch64 ]]; then
	export MAKEOPTS="-j1"
	export GOMAXPROCS=1
	# stage4 already installed the prerequisite dependency set into the stage4
	# rootfs artifact. On ARM we only need the lightweight overlay package here,
	# and asking Portage for dependency binpkgs reopens missing-binpkg failures
	# before it ever reaches the local ebuild.
	if [[ -n "$(portageq match / sys-apps/gentooha-compat 2>/dev/null || true)" ]]; then
		echo "[stage5] gentooha-compat already installed; skipping reinstall"
	else
		EMERGE_DEFAULT_OPTS="" emerge \
			--ask=n --oneshot --nodeps --jobs=1 --load-average=1 \
			sys-apps/gentooha-compat
	fi
	systemctl enable ha-os-release-sync.service
	exit 0
fi
EMERGE_DEFAULT_OPTS="" emerge "${emerge_args[@]}" sys-apps/gentooha-compat

systemctl enable ha-os-release-sync.service
CHROOT_STAGE5
)"

stage_end stage5
