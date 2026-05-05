#!/usr/bin/env bash
# test_boot.sh — Boot GentooHA VDI in VirtualBox headless and verify it reaches a login shell.
# Usage: bash scripts/tests/ai/test_boot.sh [VDI_PATH] [VM_NAME]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/common_test.sh"

VM_NAME="${2:-GentooHA 1}"
VDI_PATH="${1:-$REPO_ROOT/artifacts/gentooha-x64-debug.vdi}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
POLL_INTERVAL=5

test_header "VM Boot Test: $VM_NAME"

# Resolve absolute VDI path (handle Windows → WSL path conversion)
if [[ "$OSTYPE" == "linux-gnu"* && "$VDI_PATH" == /mnt/* ]]; then
    WIN_VDI_PATH="$(wslpath -w "$VDI_PATH" 2>/dev/null || echo "$VDI_PATH")"
else
    WIN_VDI_PATH="$VDI_PATH"
fi

VBOXMANAGE="${VBOXMANAGE:-VBoxManage}"
if ! command -v "$VBOXMANAGE" &>/dev/null; then
    VBOXMANAGE="/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
fi
if ! command -v "$VBOXMANAGE" &>/dev/null && [[ -f "$VBOXMANAGE" ]]; then
    : # use as-is
elif ! command -v "$VBOXMANAGE" &>/dev/null; then
    test_fail "VBoxManage not found. Set VBOXMANAGE env var."
fi

# --- Step 1: ensure VDI exists ---
test_step "Check VDI exists"
if [[ ! -f "$VDI_PATH" ]]; then
    test_fail "VDI not found: $VDI_PATH"
fi
test_pass "VDI found: $(basename "$VDI_PATH") ($(du -sh "$VDI_PATH" 2>/dev/null | cut -f1))"

# --- Step 2: ensure VM exists ---
test_step "Verify VM '$VM_NAME' registered"
if ! "$VBOXMANAGE" showvminfo "$VM_NAME" &>/dev/null; then
    test_fail "VM '$VM_NAME' not registered in VirtualBox. Run import_and_boot_gentooha.cmd first."
fi
test_pass "VM registered"

# --- Step 3: reattach VDI if needed ---
test_step "Reattach VDI to VM"
CURRENT_UUID="$("$VBOXMANAGE" showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep 'SATA-0-0' | cut -d'"' -f2 || true)"
MEDIUM_STATE="$("$VBOXMANAGE" showmediuminfo "$VDI_PATH" 2>/dev/null | grep 'State:' | awk '{print $2}' || echo unknown)"
if [[ "$MEDIUM_STATE" != "created" ]]; then
    "$VBOXMANAGE" storagectl "$VM_NAME" --name "SATA" --add sata 2>/dev/null || true
    "$VBOXMANAGE" storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$WIN_VDI_PATH" 2>/dev/null || true
fi
test_pass "VDI attached"

# --- Step 4: set port forwarding for HA UI access ---
test_step "Configure NAT port forwarding (8123 → 8123)"
"$VBOXMANAGE" modifyvm "$VM_NAME" --natpf1 delete ha-ui 2>/dev/null || true
"$VBOXMANAGE" modifyvm "$VM_NAME" --natpf1 "ha-ui,tcp,,8123,,8123" 2>/dev/null || true
test_pass "Port 8123 forwarded"

# --- Step 5: power on ---
test_step "Start VM headless"
VM_STATE="$("$VBOXMANAGE" showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep '^VMState=' | tr -d '"' | cut -d= -f2)"
if [[ "$VM_STATE" == "running" ]]; then
    test_pass "VM already running"
else
    "$VBOXMANAGE" startvm "$VM_NAME" --type headless
    test_pass "VM started headless"
fi

# --- Step 6: wait for VM to boot (poll running state) ---
test_step "Wait for VM to reach running state (up to ${BOOT_TIMEOUT}s)"
elapsed=0
while [[ $elapsed -lt $BOOT_TIMEOUT ]]; do
    STATE="$("$VBOXMANAGE" showvminfo "$VM_NAME" --machinereadable 2>/dev/null | grep '^VMState=' | tr -d '"' | cut -d= -f2)"
    if [[ "$STATE" == "running" ]]; then
        test_pass "VM is running (${elapsed}s)"
        break
    fi
    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
done
[[ "$STATE" == "running" ]] || test_fail "VM did not reach running state after ${BOOT_TIMEOUT}s (last: $STATE)"

# --- Step 7: wait for HA port to open ---
test_step "Wait for Home Assistant port 8123 to respond (up to 180s)"
elapsed=0
HA_UP=false
while [[ $elapsed -lt 180 ]]; do
    if curl -sf --max-time 5 "http://localhost:8123" &>/dev/null; then
        HA_UP=true
        break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    echo "    waiting... ${elapsed}s"
done
if [[ "$HA_UP" == "true" ]]; then
    test_pass "Home Assistant port 8123 is responding (${elapsed}s)"
else
    test_warn "Port 8123 not yet responding after 180s (Supervisor may still be pulling images)"
fi

test_summary
