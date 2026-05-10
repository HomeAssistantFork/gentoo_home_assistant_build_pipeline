#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_cmd awk
require_cmd grep
require_cmd sed

DOWNLOAD_DIR="${DOWNLOAD_DIR:-/var/lib/ha-gentoo-hybrid/downloads}"
ARCH="${ARCH:-amd64}"
# Stage3 init flavor is independent from build artifact flavor (live/installer/debug).
STAGE3_FLAVOR="${STAGE3_FLAVOR:-systemd}"
MIRROR_BASE="${MIRROR_BASE:-https://distfiles.gentoo.org/releases}"

# Normalize common architecture aliases used by other build stages.
case "$ARCH" in
	amd64|x86_64)
		ARCH_PATH="amd64"
		;;
	arm64|aarch64)
		ARCH_PATH="arm64"
		;;
	arm|armv7|armv7a)
		ARCH_PATH="arm"
		STAGE3_FLAVOR="${STAGE3_FLAVOR_ARM:-systemd-armv7a}"
		;;
	*)
		die "Unsupported ARCH: $ARCH (supported: amd64/x86_64, arm64/aarch64, arm/armv7a)"
		;;
esac

if [[ "$STAGE3_FLAVOR" != "systemd" && "$STAGE3_FLAVOR" != "openrc" ]]; then
	die "Unsupported STAGE3_FLAVOR: $STAGE3_FLAVOR (supported: systemd, openrc)"
fi

if command -v curl >/dev/null 2>&1; then
	FETCH_CMD="curl"
elif command -v wget >/dev/null 2>&1; then
	FETCH_CMD="wget"
else
	die "Missing downloader: install curl or wget"
fi

fetch_text() {
	local url="$1"
	if [[ "$FETCH_CMD" == "curl" ]]; then
		curl -fsSL "$url"
	else
		wget -qO- "$url"
	fi
}

download_file() {
	local url="$1"
	local out="$2"
	if [[ "$FETCH_CMD" == "curl" ]]; then
		curl -fL "$url" -o "$out"
	else
		wget -O "$out" "$url"
	fi
}

main() {
	mkdir -p "$DOWNLOAD_DIR"

	local latest_file="latest-stage3-${ARCH_PATH}-${STAGE3_FLAVOR}.txt"
	local latest_url="${MIRROR_BASE}/${ARCH_PATH}/autobuilds/${latest_file}"

	log "Fetching stage3 index: $latest_url"
	local latest_content
	latest_content="$(fetch_text "$latest_url")"

	local rel_path
	rel_path="$( (printf '%s\n' "$latest_content" | sed -E 's/#.*$//' | grep -E "stage3-[a-z0-9_]+-${STAGE3_FLAVOR}-[0-9]{8}T[0-9]{6}Z\.tar\.xz" | head -n1) || true )"

	[[ -n "$rel_path" ]] || die "Could not parse stage3 tarball path from ${latest_url}"

	rel_path="$(printf '%s' "$rel_path" | awk '{print $1}')"
	local tarball_name
	tarball_name="$(basename "$rel_path")"

	local tarball_url="${MIRROR_BASE}/${ARCH_PATH}/autobuilds/${rel_path}"
	local tarball_path="${DOWNLOAD_DIR}/${tarball_name}"

	if [[ -f "$tarball_path" ]]; then
		log "Stage3 already present: $tarball_path"
	else
		log "Downloading stage3 tarball: $tarball_url"
		download_file "$tarball_url" "$tarball_path"
	fi

	printf '%s\n' "$tarball_path"
}

main "$@"
