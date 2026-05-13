#!/usr/bin/env bash
# Preflight run INSIDE the Gentoo chroot.
# Validates all compatibility signals that must pass before first boot.
set -euo pipefail

failures=0
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '[PASS] %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name"
    failures=$((failures + 1))
  fi
}

echo "=== Gentoo Chroot Preflight ==="
check "overlay filesystem available"     grep -qw overlay /proc/filesystems
check "namespaces support"               test -d /proc/self/ns
check "runtime os-release exists"        test -f /run/os-release
check "compat os-release id homeassistant" grep -q '^ID=homeassistant' /run/os-release
check "data path exists"                 test -d /mnt/data
check "docker binary available"          command -v docker
check "os-agent binary available"        command -v os-agent
check "hassio-supervisor script"         test -x /usr/sbin/hassio-supervisor
check "hassio-supervisor service unit"   test -f /etc/systemd/system/hassio-supervisor.service
check "ha-os-release-sync service unit"  test -f /etc/systemd/system/ha-os-release-sync.service
check "docker service unit"              test -f /usr/lib/systemd/system/docker.service
check "os-agent service unit"            bash -c 'test -f /etc/systemd/system/os-agent.service || test -f /usr/lib/systemd/system/os-agent.service'
check "hassio.json present"             test -f /etc/hassio.json
check "dbus directory present"           test -d /usr/share/dbus-1
check "ha-compat os-release template"    test -f /etc/ha-compat/os-release

echo ""
if [[ "$failures" -gt 0 ]]; then
  echo "Preflight: $failures issue(s) need fixing before first boot"
  exit 1
else
  echo "Preflight: ALL CHECKS PASSED — ready for first boot"
fi
