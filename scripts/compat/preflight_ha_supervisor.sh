#!/usr/bin/env bash
set -Eeuo pipefail

failures=0
check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '[PASS] %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name"
    failures=$((failures + 1))
  fi
}

check "cgroup v2 mounted" test -f /sys/fs/cgroup/cgroup.controllers
check "overlay filesystem available" grep -qw overlay /proc/filesystems
check "namespaces support" test -d /proc/self/ns
check "veth module available" sh -c 'modprobe -n veth'
check "bridge module available" sh -c 'modprobe -n bridge'
check "netfilter module available" sh -c 'modprobe -n br_netfilter'
check "runtime os-release exists" test -f /run/os-release
check "compat os-release id homeassistant" sh -c 'grep -q "^ID=homeassistant" /run/os-release'
check "data path exists" test -d /mnt/data
check "docker command available" command -v docker
check "docker service active" systemctl is-active --quiet docker

if [[ "$failures" -gt 0 ]]; then
  echo "Preflight failed with $failures issue(s)."
  exit 1
fi

echo "Preflight successful."
