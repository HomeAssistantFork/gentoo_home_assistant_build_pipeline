#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage3
require_root
mount_chroot_fs

case "${ARCH:-amd64}" in
	x86_64|amd64)
		PORTAGE_ARCH="amd64"
		;;
	arm64|aarch64)
		PORTAGE_ARCH="arm64"
		;;
	arm)
		PORTAGE_ARCH="arm"
		;;
	*)
		PORTAGE_ARCH="${ARCH:-amd64}"
		;;
esac

GENTOO_PROFILE="${GENTOO_PROFILE:-default/linux/${PORTAGE_ARCH}/23.0/systemd}"
USE_BINPKG="${USE_BINPKG:-true}"
TIMEZONE="${TIMEZONE:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8 UTF-8}"
HOSTNAME="${HOSTNAME_OVERRIDE:-ha-gentoo}"
LANG_NAME="${LOCALE%% *}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log "Installing local gentooha overlay into chroot"
rm -rf "$TARGET_ROOT/var/db/repos/gentooha"
mkdir -p "$TARGET_ROOT/var/db/repos/gentooha"
cp -a "$REPO_ROOT/overlay/." "$TARGET_ROOT/var/db/repos/gentooha/"

log "Configuring portage and system profile inside chroot"
run_in_chroot "$(cat <<CHROOT_STAGE3
set -euo pipefail
set +u
source /etc/profile
set -u
# Ensure required directories exist (may be absent in a minimal stage3 tarball)
mkdir -p /var/tmp /var/db/repos/gentoo /var/db/repos/gentooha /var/cache/binhost
# Initial repository seed can occasionally fail transiently on mirrors.
SYNC_OK=0
for attempt in 1 2 3; do
  echo "[stage3] emerge-webrsync attempt \${attempt}/3"
  if emerge-webrsync; then
    SYNC_OK=1
    break
  fi
  echo "[stage3] emerge-webrsync failed; cleaning temporary sync state and retrying"
  rm -rf /var/db/repos/gentoo/.tmp-unverified-download-quarantine 2>/dev/null || true
  rm -f /var/db/repos/gentoo/metadata/Manifest.gz 2>/dev/null || true
  sleep 2
done
if [[ "\${SYNC_OK}" -ne 1 ]]; then
  echo "[stage3] ERROR: emerge-webrsync failed after retries"
  exit 1
fi
if ! command -v eselect >/dev/null 2>&1; then
  emerge --ask=n app-admin/eselect
fi
mkdir -p /etc/portage
if [[ -f /etc/portage/make.conf ]]; then
  sed -i -E '/^ARCH=/d' /etc/portage/make.conf
fi
printf 'ARCH="%s"\n' '${PORTAGE_ARCH}' >> /etc/portage/make.conf

# Binary package support
if [[ '${USE_BINPKG}' == 'true' ]]; then
  echo "[stage3] Configuring binary package host"
  sed -i -E '/^FEATURES=|^EMERGE_DEFAULT_OPTS=|^PORTAGE_BINHOST=|^PORTAGE_GPG_DIR=/d' /etc/portage/make.conf
  printf 'FEATURES="getbinpkg"\n' >> /etc/portage/make.conf
  printf 'EMERGE_DEFAULT_OPTS="--getbinpkg --binpkg-respect-use=y"\n' >> /etc/portage/make.conf
  printf 'PORTAGE_BINHOST="https://packages.gentoo.org/packages/index.gpkg.tar"\n' >> /etc/portage/make.conf
  printf 'PORTAGE_GPG_DIR="/etc/portage/gnupg"\n' >> /etc/portage/make.conf
  mkdir -p /etc/portage/binrepos.conf
  if [[ -f /etc/portage/binrepos.conf/gentoo.conf ]]; then
    sed -i -E 's/^verify-signature *=.*/verify-signature = false/' /etc/portage/binrepos.conf/gentoo.conf
  else
    cat >/etc/portage/binrepos.conf/gentoo.conf <<'EOF'
[gentoo]
priority = 1
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
location = /var/cache/binhost/gentoo
verify-signature = false
EOF
  fi
  mkdir -p /etc/portage/gnupg
  chown -R root:root /etc/portage/gnupg
  chmod 700 /etc/portage/gnupg
  if command -v getuto >/dev/null 2>&1; then
    echo "[stage3] Initializing Gentoo binpkg trust"
    getuto || true
  else
    echo "[stage3] WARNING: getuto not available; binpkg signature verification may fail"
  fi
  if id -u portage >/dev/null 2>&1; then
    chown -R portage:portage /etc/portage/gnupg
  else
    chown -R root:root /etc/portage/gnupg
  fi
  find /etc/portage/gnupg -type d -exec chmod 700 {} +
  find /etc/portage/gnupg -type f -exec chmod 600 {} +
else
  echo "[stage3] Binary packages disabled — building from source"
  sed -i -E '/^FEATURES=.*getbinpkg|^EMERGE_DEFAULT_OPTS=.*getbinpkg|^PORTAGE_BINHOST=|^PORTAGE_GPG_DIR=/d' /etc/portage/make.conf || true
fi

mkdir -p /etc/portage/repos.conf
cat >/etc/portage/repos.conf/gentooha.conf <<'EOF'
[gentooha]
location = /var/db/repos/gentooha
masters = gentoo
auto-sync = no
EOF

if [[ -f /etc/portage/repos.conf/gentoo.conf ]]; then
  if grep -q '^sync-openpgp-key-refresh' /etc/portage/repos.conf/gentoo.conf; then
    sed -i -E 's/^sync-openpgp-key-refresh *=.*/sync-openpgp-key-refresh = false-nowarn/' /etc/portage/repos.conf/gentoo.conf
  else
    printf 'sync-openpgp-key-refresh = false-nowarn\n' >> /etc/portage/repos.conf/gentoo.conf
  fi
else
  cat >/etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
sync-uri = https://sync.gentoo.org/git/sync/gentoo-portage.git
location = /var/db/repos/gentoo
sync-openpgp-key-refresh = false-nowarn
EOF
fi

if command -v eselect >/dev/null 2>&1; then
  ARCH='${PORTAGE_ARCH}' eselect profile set '${GENTOO_PROFILE}' || true
fi
# Follow-up sync can fail on transient Manifest mismatch. Retry with cleanup.
SYNC_OK=0
for attempt in 1 2 3; do
  echo "[stage3] emerge --sync attempt \${attempt}/3"
  if emerge --sync; then
    SYNC_OK=1
    break
  fi
  echo "[stage3] emerge --sync failed; cleaning temporary sync state and retrying"
  rm -rf /var/db/repos/gentoo/.tmp-unverified-download-quarantine 2>/dev/null || true
  rm -f /var/db/repos/gentoo/metadata/Manifest.gz 2>/dev/null || true
  if command -v emaint >/dev/null 2>&1; then
    emaint sync -r gentoo --auto 2>/dev/null || true
  fi
  sleep 2
done
if [[ "\${SYNC_OK}" -ne 1 ]]; then
  echo "[stage3] ERROR: emerge --sync failed after retries"
  exit 1
fi
emerge --ask=n -uDN @world
printf '%s\n' "${TIMEZONE}" > /etc/timezone
emerge --config sys-libs/timezone-data
printf '%s\n' "${LOCALE}" > /etc/locale.gen
locale-gen
printf 'LANG=%s\n' "${LANG_NAME}" > /etc/env.d/02locale
env-update
set +u
source /etc/profile
set -u
printf 'hostname=%s\n' "${HOSTNAME}" > /etc/conf.d/hostname
CHROOT_STAGE3
)"

log "Enabling baseline services"
run_in_chroot "$(cat <<'CHROOT_STAGE3_SERVICES'
set -euo pipefail
systemctl enable systemd-networkd systemd-resolved
CHROOT_STAGE3_SERVICES
)"

stage_end stage3
