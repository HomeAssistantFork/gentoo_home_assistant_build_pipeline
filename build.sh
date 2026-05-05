#!/usr/bin/env bash
# GentooHA build launcher
# Usage: bash build.sh [--non-interactive]
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NON_INTERACTIVE=false
for arg in "$@"; do [[ "$arg" == "--non-interactive" ]] && NON_INTERACTIVE=true; done

# Capture whether START_STAGE was explicitly provided by the caller before we
# apply auto-resume logic further down.
START_STAGE_EXPLICIT="${START_STAGE:-}"

_OS="$(uname -s 2>/dev/null || echo unknown)"
case "$_OS" in
  MINGW*|MSYS*|CYGWIN*) _ENV="windows-bash" ;;
  Linux*)
    if grep -qsi microsoft /proc/version 2>/dev/null; then
      _ENV="wsl"
    else
      _ENV="linux"
    fi
    ;;
  Darwin*|FreeBSD*|OpenBSD*|NetBSD*) _ENV="unsupported-unix" ;;
  *) _ENV="unknown" ;;
esac

echo "[build.sh] Environment: $_ENV ($(uname -sr 2>/dev/null || echo ?))"

# Decision table:
#   windows-bash  (Git Bash / MSYS2 / Cygwin on Windows) -> delegate to WSL2
#   wsl           (already inside WSL2 Linux)             -> run directly on this Linux
#   linux         (native Linux host)                    -> run directly on this Linux
#   anything else -> unsupported
if [[ "$_ENV" == "unsupported-unix" || "$_ENV" == "unknown" ]]; then
  echo "ERROR: Build stages require Linux (native Linux or WSL2)."
  exit 1
fi

VALID_PLATFORMS=(x64 pi3 pi4 pizero2 bbb pbv2)
VALID_FLAVORS=(live installer debug)

if $NON_INTERACTIVE; then
  PLATFORM="${PLATFORM:-x64}"
  FLAVOR="${FLAVOR:-installer}"
  START_STAGE="${START_STAGE:-1}"
  CLEAN_STATE="${CLEAN_STATE:-false}"
  ARTIFACT_ACTION="${ARTIFACT_ACTION:-a}"
else
  echo "============================================================"
  echo " GentooHA Build Launcher"
  echo "============================================================"
  echo ""
  echo "Platforms:"
  echo "  x64      - Generic PC / VM (produces preinstalled .img + .vdi)"
  echo "  pi3      - Raspberry Pi 3 (produces .img)"
  echo "  pi4      - Raspberry Pi 4 (produces .img)"
  echo "  pizero2  - Raspberry Pi Zero 2 W (produces .img)"
  echo "  bbb      - BeagleBone Black (produces .img)"
  echo "  pbv2     - PocketBeagle v2 with GPU (produces .img)"
  echo ""
  while true; do
    read -rp "Platform [x64]: " PLATFORM
    PLATFORM="${PLATFORM:-x64}"
    if [[ " ${VALID_PLATFORMS[*]} " =~ " ${PLATFORM} " ]]; then break; fi
    echo "Invalid platform. Choose from: ${VALID_PLATFORMS[*]}"
  done

  echo ""
  echo "Flavors:"
  echo "  live       - Bootable live system (does not install)"
  echo "  installer  - Asks to install to disk on first boot"
  echo "  debug      - Verbose boot diagnostics on console"
  echo ""
  while true; do
    read -rp "Flavor [installer]: " FLAVOR
    FLAVOR="${FLAVOR:-installer}"
    if [[ " ${VALID_FLAVORS[*]} " =~ " ${FLAVOR} " ]]; then break; fi
    echo "Invalid flavor. Choose from: ${VALID_FLAVORS[*]}"
  done

  echo ""
  while true; do
    read -rp "Start from stage (1-12) [1]: " START_STAGE
    START_STAGE="${START_STAGE:-1}"
    if [[ "$START_STAGE" =~ ^[0-9]+$ ]] && [[ "$START_STAGE" -ge 1 ]] && [[ "$START_STAGE" -le 12 ]]; then break; fi
    echo "Enter a number from 1 to 12."
  done

  echo ""
  read -rp "Clean prior stage state? (y/N) [N]: " CLEAN_ANS
  CLEAN_STATE="false"
  [[ "${CLEAN_ANS,,}" == "y" ]] && CLEAN_STATE="true"

  echo ""
  while true; do
    read -rp "Handle existing artifacts? archive/remove/keep (a/y/n) [a]: " ARTIFACT_ACTION
    ARTIFACT_ACTION="${ARTIFACT_ACTION:-a}"
    case "${ARTIFACT_ACTION,,}" in
      a|y|n) break ;;
      *) echo "Invalid choice. Use: a (archive), y (remove), n (keep)." ;;
    esac
  done

  echo ""
  echo "============================================================"
  echo " Build summary"
  echo "   PLATFORM    = $PLATFORM"
  echo "   FLAVOR      = $FLAVOR"
  echo "   START_STAGE = $START_STAGE"
  echo "   CLEAN_STATE = $CLEAN_STATE"
  echo "   ARTIFACTS   = ${ARTIFACT_ACTION,,} (a=archive, y=remove, n=keep)"
  echo "============================================================"
  echo ""
  read -rp "Proceed? (Y/n) [Y]: " PROCEED
  [[ "${PROCEED,,}" == "n" ]] && { echo "Aborted."; exit 0; }
fi

ARTIFACT_ACTION="${ARTIFACT_ACTION,,}"
case "$ARTIFACT_ACTION" in
  a|y|n) ;;
  *) ARTIFACT_ACTION="a" ;;
esac

handle_artifacts() {
  local artifacts_dir="$SCRIPT_DIR/artifacts"
  mkdir -p "$artifacts_dir"

  case "$ARTIFACT_ACTION" in
    a)
      if find "$artifacts_dir" -mindepth 1 -maxdepth 1 ! -name archive | read -r; then
        local ts archive_dir
        ts="$(date +%Y%m%d_%H%M%S)"
        archive_dir="$artifacts_dir/archive/$ts"
        mkdir -p "$archive_dir"
        find "$artifacts_dir" -mindepth 1 -maxdepth 1 ! -name archive -exec mv -f {} "$archive_dir" \;
        echo "[build.sh] Archived existing artifacts to: $archive_dir"
      else
        echo "[build.sh] No existing artifacts to archive."
      fi
      ;;
    y)
      if find "$artifacts_dir" -mindepth 1 -maxdepth 1 | read -r; then
        find "$artifacts_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
        echo "[build.sh] Removed existing artifacts from: $artifacts_dir"
      else
        echo "[build.sh] No existing artifacts to remove."
      fi
      ;;
    n)
      echo "[build.sh] Keeping existing artifacts in: $artifacts_dir"
      ;;
  esac
}

handle_artifacts

# ── Auto-resume: advance START_STAGE to last completed+1 ──────────────────
STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"
COMPLETED_STAGE_FILE="${STATE_ROOT}/completed_stage"
MAX_STAGE=12

if [[ "$_ENV" != "windows-bash" ]]; then
  if [[ -f "$COMPLETED_STAGE_FILE" ]]; then
    COMPLETED="$(cat "$COMPLETED_STAGE_FILE" 2>/dev/null | tr -dc '0-9' || true)"
    if [[ -n "$COMPLETED" ]] && [[ "$COMPLETED" -ge 1 ]]; then
      if [[ "$COMPLETED" -ge "$MAX_STAGE" ]]; then
        echo "[build.sh] All $MAX_STAGE stages already completed. Nothing to do."
        echo "           Run reset.sh to clear stage tracking and rebuild from scratch."
        exit 0
      fi
      # Only auto-advance if the user did NOT explicitly set START_STAGE
      if [[ -z "$START_STAGE_EXPLICIT" ]] || [[ "$START_STAGE" -le "$COMPLETED" ]]; then
        AUTO_START=$(( COMPLETED + 1 ))
        echo "[build.sh] Resuming from stage $AUTO_START (completed_stage=$COMPLETED)."
        START_STAGE="$AUTO_START"
      fi
    fi
  fi
fi

export PLATFORM FLAVOR START_STAGE CLEAN_STATE ARTIFACT_ACTION

# ── Windows path (Git Bash / MSYS2 / Cygwin) ──────────────────────────────
# build.sh cannot run build stages here; delegate to WSL2.
if [[ "$_ENV" == "windows-bash" ]]; then
  echo "[build.sh] Windows shell detected — delegating to WSL2."
  WSL_DISTRO=""
  if wsl -d GentooHA -- echo ok >/dev/null 2>&1; then
    WSL_DISTRO="GentooHA"
  elif wsl -d Debian -- echo ok >/dev/null 2>&1; then
    WSL_DISTRO="Debian"
  fi
  if [[ -z "$WSL_DISTRO" ]]; then
    echo "ERROR: No suitable WSL2 distro found (need GentooHA or Debian)."
    echo "Run scripts/windows/prereq_wsl_debian.cmd first."
    exit 1
  fi
  WSL_PATH="$(wsl wslpath "$(pwd -W)" 2>/dev/null || true)"
  if [[ -z "$WSL_PATH" ]]; then
    WSL_PATH="$(echo "$SCRIPT_DIR" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|; s|\\|/|g')"
  fi
  echo "[build.sh] WSL distro: $WSL_DISTRO  path: $WSL_PATH"
  wsl -d "$WSL_DISTRO" -- bash -c \
    "export PLATFORM='$PLATFORM' FLAVOR='$FLAVOR' START_STAGE='$START_STAGE' CLEAN_STATE='$CLEAN_STATE' ARTIFACT_ACTION='$ARTIFACT_ACTION' END_STAGE='${END_STAGE:-}'; cd '$WSL_PATH' && bash build.sh --non-interactive"
  exit $?
fi

# ── Linux path (native Linux or already inside WSL2) ───────────────────────
# Run build stages directly on this Linux environment.
echo "[build.sh] Linux environment ($_ENV) — running build stages directly."
if [[ "$CLEAN_STATE" == "true" ]]; then
  STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"
  echo "Cleaning stage state files in $STATE_ROOT ..."
  rm -f "$STATE_ROOT"/stage*.done "$STATE_ROOT"/completed_stage 2>/dev/null || true
fi

echo ""
echo "Starting build: PLATFORM=$PLATFORM FLAVOR=$FLAVOR START_STAGE=$START_STAGE END_STAGE=${END_STAGE:-12}"
bash "$SCRIPT_DIR/scripts/gentoo/run_all.sh"
