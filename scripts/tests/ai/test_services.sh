#!/usr/bin/env bash
# test_services.sh — Verify Docker, os-agent, and hassio-supervisor are active inside GentooHA VM.
# Usage: bash scripts/tests/ai/test_services.sh [VM_NAME]
# Requires: VM is running, VBoxManage available, or GentooHA WSL distro running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_test.sh"

VM_NAME="${1:-GentooHA 1}"
VBOXMANAGE="${VBOXMANAGE:-/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe}"

test_header "GentooHA Service Tests: $VM_NAME"

# Detect whether to use VM guest control or WSL direct
USE_WSL=false
if wsl -d GentooHA -- bash -c "echo ok" &>/dev/null 2>&1; then
    USE_WSL=true
    test_info "Using WSL GentooHA distro for service checks"
else
    test_info "Using VBoxManage guest control for service checks"
fi

vm_exec() {
    if [[ "$USE_WSL" == "true" ]]; then
        wsl -d GentooHA -- bash -c "$1" 2>&1
    else
        run_in_vm "$1"
    fi
}

check_service() {
    local svc="$1"
    local label="${2:-$1}"
    test_step "Check $label"
    local status
    status="$(vm_exec "systemctl is-active $svc 2>/dev/null || echo unknown")" || status="exec-failed"
    case "$status" in
        active)   test_pass "$label is active" ;;
        inactive) test_warn "$label is inactive (may still be starting)" ;;
        failed)
            test_warn "$label is in failed state — journal:"
            vm_exec "journalctl -u $svc -n 30 --no-pager 2>/dev/null || true" | sed 's/^/    /' || true
            TESTS_FAILED=$((TESTS_FAILED+1))
            ;;
        *)        test_warn "$label status: $status" ;;
    esac
}

# --- systemd health ---
test_step "Check systemd is running"
SYSTEMD_STATE="$(vm_exec "systemctl is-system-running 2>/dev/null || echo unknown")" || SYSTEMD_STATE="unknown"
case "$SYSTEMD_STATE" in
    running|degraded) test_pass "systemd state: $SYSTEMD_STATE" ;;
    *) test_warn "systemd state: $SYSTEMD_STATE (may still be booting)" ;;
esac

# --- Core services ---
check_service "docker"             "Docker"
check_service "containerd"         "containerd"
check_service "os-agent"           "os-agent (HA OS Agent)"
check_service "hassio-supervisor"  "hassio-supervisor (HA Supervisor)"

# --- Docker functional check ---
test_step "Docker daemon functional (docker info)"
DOCKER_INFO="$(vm_exec "docker info --format '{{.ServerVersion}}' 2>/dev/null || echo FAILED")" || DOCKER_INFO="FAILED"
if [[ "$DOCKER_INFO" == "FAILED" || -z "$DOCKER_INFO" ]]; then
    test_warn "docker info failed — Docker may not be ready yet"
else
    test_pass "Docker daemon version: $DOCKER_INFO"
fi

# --- hassio_supervisor container ---
test_step "hassio_supervisor container running"
CONTAINER="$(vm_exec "docker inspect --format='{{.State.Status}}' hassio_supervisor 2>/dev/null || echo missing")" || CONTAINER="missing"
case "$CONTAINER" in
    running) test_pass "hassio_supervisor container is running" ;;
    missing) test_warn "hassio_supervisor container not yet created (Supervisor may be pulling image)" ;;
    *)       test_warn "hassio_supervisor container state: $CONTAINER" ;;
esac

# --- IPv4 forwarding ---
test_step "IPv4 forwarding enabled"
FWD="$(vm_exec "cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0")" || FWD="0"
if [[ "$FWD" == "1" ]]; then
    test_pass "IPv4 forwarding is enabled"
else
    test_warn "IPv4 forwarding is disabled — Docker networking may be broken"
fi

# --- iptables ---
test_step "iptables functional"
IPTS="$(vm_exec "iptables -L INPUT --line-numbers 2>/dev/null | head -3 || echo FAILED")" || IPTS="FAILED"
if [[ "$IPTS" == *"FAILED"* ]]; then
    test_warn "iptables check failed — check kernel netfilter config"
else
    test_pass "iptables is functional"
fi

test_summary
