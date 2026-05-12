#!/usr/bin/env bash
# reset.sh — Clear GentooHA stage-tracking state so the next build.sh run
#             starts from stage 1.  Safe to run at any time; does not delete
#             the built rootfs or artifact files.
set -Eeuo pipefail

STATE_ROOT="${STATE_ROOT:-/var/lib/ha-gentoo-hybrid/state}"

_OS="$(uname -s 2>/dev/null || echo unknown)"
case "$_OS" in
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash on Windows: delegate to WSL
    echo "[reset.sh] Windows shell detected — delegating to WSL2."
    WSL_DISTRO=""
    wsl -d Debian -- echo ok >/dev/null 2>&1 && WSL_DISTRO="Debian"
    [[ -z "$WSL_DISTRO" ]] && WSL_DISTRO="$(wsl -l -q 2>/dev/null | head -1 | tr -d '\r')"
    if [[ -z "$WSL_DISTRO" ]]; then
      echo "ERROR: No WSL2 distro found. Cannot clear state."
      exit 1
    fi
    wsl -d "$WSL_DISTRO" -u root -- bash -c "
      STATE_ROOT='${STATE_ROOT}'
      mkdir -p \"\$STATE_ROOT\"
      rm -f \"\$STATE_ROOT\"/stage*.done \"\$STATE_ROOT\"/completed_stage
      echo '[reset] Stage tracking cleared.'
      echo '[reset] Next build.sh run will start from stage 1.'
    "
    exit $?
    ;;
esac

# Native Linux / WSL
mkdir -p "$STATE_ROOT"
rm -f "${STATE_ROOT}"/stage*.done "${STATE_ROOT}"/completed_stage 2>/dev/null || true
echo "[reset] Stage tracking cleared (${STATE_ROOT})."
echo "[reset] Next build.sh run will start from stage 1."
