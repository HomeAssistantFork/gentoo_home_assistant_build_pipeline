#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

stage_start stage5
require_root
mount_chroot_fs

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
import pathlib, re

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

	# 2. Wrap _create_pty_or_pipe so any termios.error falls back to a plain pipe.
	#    This guards against qemu-user ENOTTY even when openpty is disabled.
	GUARD_MARKER = '# [stage5-qemu-guard]'
	if GUARD_MARKER not in txt:
		# Find the function definition line and inject a try/except wrapper around
		# the termios call inside it by replacing the whole function body with a
		# safe version that catches termios.error.
		old_fn = 'def _create_pty_or_pipe(copy_term_settings=None):'
		new_wrapper = (
			'def _create_pty_or_pipe(copy_term_settings=None):  ' + GUARD_MARKER + '\n'
			'\timport os as _os\n'
			'\ttry:\n'
			'\t\treturn _create_pty_or_pipe_real(copy_term_settings=copy_term_settings)\n'
			'\texcept Exception:\n'
			'\t\tr, w = _os.pipe()\n'
			'\t\treturn False, r, w\n'
			'\n'
			'def _create_pty_or_pipe_real(copy_term_settings=None):'
		)
		if old_fn in txt:
			txt = txt.replace(old_fn, new_wrapper, 1)
			changed = True
			print(f'[stage5] Wrapped _create_pty_or_pipe with pipe fallback: {p}')
		else:
			print(f'[stage5] WARNING: could not find _create_pty_or_pipe to wrap in {p}')

	if changed:
		p.write_text(txt, encoding='utf-8')
PY
fi

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
if command -v script >/dev/null 2>&1; then
	script -q -e -c 'EMERGE_DEFAULT_OPTS="" emerge --ask=n --getbinpkg --usepkg --binpkg-respect-use=y --noreplace sys-apps/gentooha-compat' /dev/null
else
	EMERGE_DEFAULT_OPTS="" emerge --ask=n --getbinpkg --usepkg --binpkg-respect-use=y --noreplace sys-apps/gentooha-compat
fi

systemctl enable ha-os-release-sync.service
CHROOT_STAGE5
)"

stage_end stage5
