#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage1
require_root

log "Installing host prerequisites (Debian bootstrap host path)."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install \
    debootstrap gdisk parted wget curl git rsync xz-utils tar

  # Install cross-compilation toolchain and QEMU binfmt for ARM target platforms.
  # This allows ARM chroot binaries (emerge, sh, etc.) to run on the x64 build host.
  case "${ARCH:-}" in
    arm|armv7|armv7a)
      log "ARM32 target: installing cross-compiler and QEMU user-mode emulation"
      DEBIAN_FRONTEND=noninteractive apt-get -y install \
        gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
        qemu-user-static binfmt-support
      update-binfmts --enable qemu-arm 2>/dev/null || true
      ;;
    arm64|aarch64)
      log "ARM64 target: installing cross-compiler and QEMU user-mode emulation"
      DEBIAN_FRONTEND=noninteractive apt-get -y install \
        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        qemu-user-static binfmt-support
      update-binfmts --enable qemu-aarch64 2>/dev/null || true
      ;;
  esac
else
  warn "apt-get not found. Install host tools manually for your distro."
fi

log "Preparing TARGET_ROOT at $TARGET_ROOT"
mkdir -p "$TARGET_ROOT"

# Ensure stage2 can extract stage3 cleanly on retries/reruns.
if [[ -d "$TARGET_ROOT" ]]; then
  if [[ "$TARGET_ROOT" == "/" || "$TARGET_ROOT" == "." || "$TARGET_ROOT" == "" ]]; then
    die "Refusing to clean unsafe TARGET_ROOT='$TARGET_ROOT'"
  fi
  find "$TARGET_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

mkdir -p "$TARGET_ROOT"/{etc,usr,var,boot,home,root,tmp}
chmod 1777 "$TARGET_ROOT/tmp"

log "Stage1 host preparation complete."
stage_end stage1
