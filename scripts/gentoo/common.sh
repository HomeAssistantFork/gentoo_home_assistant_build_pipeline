#!/usr/bin/env bash
set -Eeuo pipefail

STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"
TARGET_ROOT="${TARGET_ROOT:-/mnt/gentoo}"

# Build target platform and flavor
# PLATFORM: x64 | pi3 | pi4 | pizero2 | bbb | pbv2
# FLAVOR:   live | installer | debug
PLATFORM="${PLATFORM:-x64}"
FLAVOR="${FLAVOR:-live}"
X64_ARTIFACT_FORMATS="${X64_ARTIFACT_FORMATS:-${X64_ARTIFACT_FORMAT:-vdi}}"
BUILD_UML_KERNEL="${BUILD_UML_KERNEL:-false}"

case "$FLAVOR" in
  live|installer|debug)
    ;;
  *)
    echo "ERROR: Unknown FLAVOR='$FLAVOR'. Valid: live installer debug" >&2
    exit 1
    ;;
esac

case "$PLATFORM" in
  x64)
    ARCH="x86_64"
    CROSS_COMPILE=""
    case " $X64_ARTIFACT_FORMATS " in
      *" vdi "*) ARTIFACT_EXT="vdi" ;;
      *" vhd "*) ARTIFACT_EXT="vhd" ;;
      *" iso "*) ARTIFACT_EXT="iso" ;;
      *" img "*) ARTIFACT_EXT="img" ;;
      *)
        echo "ERROR: Unknown X64_ARTIFACT_FORMATS='$X64_ARTIFACT_FORMATS'. Valid tokens: vhd vdi iso img" >&2
        exit 1
        ;;
    esac
    ;;
  pi3|bbb)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    ARTIFACT_EXT="img"
    ;;
  pi4|pizero2|pbv2)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    ARTIFACT_EXT="img"
    ;;
  *)
    echo "ERROR: Unknown PLATFORM='$PLATFORM'. Valid: x64 pi3 pi4 pizero2 bbb pbv2" >&2
    exit 1
    ;;
esac

X64_ARTIFACT_FORMAT="$X64_ARTIFACT_FORMATS"

export PLATFORM FLAVOR ARCH CROSS_COMPILE ARTIFACT_EXT X64_ARTIFACT_FORMAT X64_ARTIFACT_FORMATS BUILD_UML_KERNEL

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
warn() { log "WARN: $*"; }
die() { log "ERROR: $*"; exit 1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This stage must run as root"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

ensure_state_root() {
  mkdir -p "$STATE_ROOT"
}

is_done() {
  local stage="$1"
  [[ -f "$STATE_ROOT/${stage}.done" ]]
}

mark_done() {
  local stage="$1"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE_ROOT/${stage}.done"
}

stage_start() {
  local stage="$1"
  log "Starting ${stage}"
  ensure_state_root
  if is_done "$stage"; then
    log "Stage ${stage} already completed. Skipping."
    exit 0
  fi
}

stage_end() {
  local stage="$1"
  mark_done "$stage"
  if [[ "$stage" =~ ^stage([0-9]+) ]]; then
    local num="${BASH_REMATCH[1]}"
    local prev=0
    [[ -f "$STATE_ROOT/completed_stage" ]] && prev="$(cat "$STATE_ROOT/completed_stage" 2>/dev/null || echo 0)"
    if [[ "$num" -gt "$prev" ]]; then
      echo "$num" > "$STATE_ROOT/completed_stage"
    fi
  fi
  log "Completed ${stage}"
}

mount_chroot_fs() {
  mkdir -p "$TARGET_ROOT"/{proc,sys,dev,run}
  mountpoint -q "$TARGET_ROOT/proc" || mount -t proc /proc "$TARGET_ROOT/proc"
  mountpoint -q "$TARGET_ROOT/sys" || mount --rbind /sys "$TARGET_ROOT/sys"
  mountpoint -q "$TARGET_ROOT/dev" || mount --rbind /dev "$TARGET_ROOT/dev"
  mountpoint -q "$TARGET_ROOT/run" || mount --bind /run "$TARGET_ROOT/run"
}

ensure_portage_cache_dirs() {
  run_in_chroot '
set -euo pipefail

if id -u portage >/dev/null 2>&1 && getent group portage >/dev/null 2>&1; then
  install -d -m 2775 -o root -g portage /var/cache/distfiles /var/cache/distfiles/git3-src /var/tmp/portage
else
  install -d -m 0755 /var/cache/distfiles /var/cache/distfiles/git3-src /var/tmp/portage
fi
'
}

run_in_chroot() {
  local script="$1"
  case "${ARCH:-}" in
    arm|armv7|armv7a)
      # Prefer binfmt-managed execution when available; fall back to explicit qemu.
      if chroot "$TARGET_ROOT" /bin/true >/dev/null 2>&1; then
        chroot "$TARGET_ROOT" /bin/bash -lc "$script"
      else
        [[ -x "$TARGET_ROOT/usr/bin/qemu-arm-static" ]] || die "Missing $TARGET_ROOT/usr/bin/qemu-arm-static for ARM chroot execution"
        chroot "$TARGET_ROOT" /usr/bin/qemu-arm-static /bin/bash -lc "$script"
      fi
      ;;
    arm64|aarch64)
      # Prefer binfmt-managed execution when available; fall back to explicit qemu.
      if chroot "$TARGET_ROOT" /bin/true >/dev/null 2>&1; then
        chroot "$TARGET_ROOT" /bin/bash -lc "$script"
      else
        [[ -x "$TARGET_ROOT/usr/bin/qemu-aarch64-static" ]] || die "Missing $TARGET_ROOT/usr/bin/qemu-aarch64-static for ARM64 chroot execution"
        chroot "$TARGET_ROOT" /usr/bin/qemu-aarch64-static /bin/bash -lc "$script"
      fi
      ;;
    *)
      chroot "$TARGET_ROOT" /bin/bash -lc "$script"
      ;;
  esac
}
