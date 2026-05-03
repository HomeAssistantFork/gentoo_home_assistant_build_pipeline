#!/usr/bin/env bash
# GentooHA local build launcher
# Usage: bash build.sh [--non-interactive]
#
# This script runs entirely inside the current Linux environment.
# It works on native Linux, inside a WSL2 distro, or inside a CI runner.
# No WSL is installed or required when running natively on Linux.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NON_INTERACTIVE=false
for arg in "$@"; do [[ "$arg" == "--non-interactive" ]] && NON_INTERACTIVE=true; done

# Detect execution environment and log it so the operator knows where stages will run.
if grep -qsi microsoft /proc/version 2>/dev/null; then
  echo "[build.sh] Environment: WSL2 ($(uname -r))"
elif [[ -f /proc/version ]]; then
  echo "[build.sh] Environment: native Linux ($(uname -r))"
fi

VALID_PLATFORMS=(x64 pi3 pi4 pizero2 bbb pbv2)
VALID_FLAVORS=(live installer)

if $NON_INTERACTIVE; then
  # CI mode: read entirely from environment
  PLATFORM="${PLATFORM:-x64}"
  FLAVOR="${FLAVOR:-live}"
  START_STAGE="${START_STAGE:-1}"
  CLEAN_STATE="${CLEAN_STATE:-false}"
else
  # Interactive mode
  echo "============================================================"
  echo " GentooHA Build Launcher"
  echo "============================================================"
  echo ""
  echo "Platforms:"
  echo "  x64      - Generic PC / VM (produces .iso)"
  echo "  pi3      - Raspberry Pi 3 (produces .img)"
  echo "  pi4      - Raspberry Pi 4 (produces .img)"
  echo "  pizero2  - Raspberry Pi Zero 2 W (produces .img)"
  echo "  bbb      - BeagleBone Black (produces .img)"
  echo "  pbv2     - PocketBeagle v2 with GPU (produces .img)"
  echo ""
  while true; do
    read -rp "Platform [x64]: " PLATFORM
    PLATFORM="${PLATFORM:-x64}"
    # shellcheck disable=SC2076
    if [[ " ${VALID_PLATFORMS[*]} " =~ " ${PLATFORM} " ]]; then break; fi
    echo "Invalid platform. Choose from: ${VALID_PLATFORMS[*]}"
  done

  echo ""
  echo "Flavors:"
  echo "  live       - Bootable live system (does not install)"
  echo "  installer  - Asks to install to disk on first boot"
  echo ""
  while true; do
    read -rp "Flavor [live]: " FLAVOR
    FLAVOR="${FLAVOR:-live}"
    # shellcheck disable=SC2076
    if [[ " ${VALID_FLAVORS[*]} " =~ " ${FLAVOR} " ]]; then break; fi
    echo "Invalid flavor. Choose from: ${VALID_FLAVORS[*]}"
  done

  echo ""
  while true; do
    read -rp "Start from stage (1-10) [1]: " START_STAGE
    START_STAGE="${START_STAGE:-1}"
    if [[ "$START_STAGE" =~ ^[0-9]+$ ]] && [[ "$START_STAGE" -ge 1 ]] && [[ "$START_STAGE" -le 10 ]]; then break; fi
    echo "Enter a number from 1 to 10."
  done

  echo ""
  read -rp "Clean prior stage state? (y/N) [N]: " CLEAN_ANS
  CLEAN_STATE="false"
  [[ "${CLEAN_ANS,,}" == "y" ]] && CLEAN_STATE="true"

  echo ""
  echo "============================================================"
  echo " Build summary"
  echo "   PLATFORM    = $PLATFORM"
  echo "   FLAVOR      = $FLAVOR"
  echo "   START_STAGE = $START_STAGE"
  echo "   CLEAN_STATE = $CLEAN_STATE"
  echo "============================================================"
  echo ""
  read -rp "Proceed? (Y/n) [Y]: " PROCEED
  [[ "${PROCEED,,}" == "n" ]] && { echo "Aborted."; exit 0; }
fi

export PLATFORM FLAVOR START_STAGE CLEAN_STATE

# Clean state files if requested
if [[ "$CLEAN_STATE" == "true" ]]; then
  STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"
  echo "Cleaning stage state files in $STATE_ROOT ..."
  rm -f "$STATE_ROOT"/stage*.done 2>/dev/null || true
fi

echo ""
echo "Starting build: PLATFORM=$PLATFORM FLAVOR=$FLAVOR START_STAGE=$START_STAGE"
bash "$SCRIPT_DIR/scripts/gentoo/run_all.sh"
