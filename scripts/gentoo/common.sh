#!/usr/bin/env bash
set -Eeuo pipefail

STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"
TARGET_ROOT="${TARGET_ROOT:-/mnt/gentoo}"

# Build target platform and flavor
# PLATFORM: x64 | pi3 | pi4 | pizero2 | bbb | pbv2
# FLAVOR:   live | installer
PLATFORM="${PLATFORM:-x64}"
FLAVOR="${FLAVOR:-live}"

case "$PLATFORM" in
  x64)
    ARCH="x86_64"
    CROSS_COMPILE=""
    ARTIFACT_EXT="iso"
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

export PLATFORM FLAVOR ARCH CROSS_COMPILE ARTIFACT_EXT

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
  # Track the highest completed stage so the next job's rootfs can auto-skip.
  local num="${stage#stage}"
  local prev=0
  [[ -f "$STATE_ROOT/completed_stage" ]] && prev="$(cat "$STATE_ROOT/completed_stage")"
  if [[ "$num" -gt "$prev" ]]; then
    echo "$num" > "$STATE_ROOT/completed_stage"
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

run_in_chroot() {
  local script="$1"
  chroot "$TARGET_ROOT" /bin/bash -lc "$script"
}
