#!/usr/bin/env bash
# test_supervisor.sh — Test Supervisor API and add-on lifecycle inside GentooHA.
# Requires: hassio-supervisor running, HA_TOKEN or SUPERVISOR_TOKEN set.
# Usage: bash scripts/tests/ai/test_supervisor.sh [SUPERVISOR_TOKEN]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_test.sh"

export SUPERVISOR_TOKEN="${1:-${SUPERVISOR_TOKEN:-}}"
SUPERVISOR_URL="${SUPERVISOR_URL:-http://localhost:8123/api/hassio}"
VM_NAME="${VM_NAME:-GentooHA 1}"

test_header "Home Assistant Supervisor Tests"

# --- Detect exec method ---
USE_WSL=false
if wsl -d GentooHA -- bash -c "echo ok" &>/dev/null 2>&1; then
    USE_WSL=true
fi

vm_exec() {
    if [[ "$USE_WSL" == "true" ]]; then
        wsl -d GentooHA -- bash -c "$1" 2>&1
    else
        run_in_vm "$1"
    fi
}

# --- Token availability ---
test_step "Check for Supervisor token"
if [[ -z "$SUPERVISOR_TOKEN" ]]; then
    # Try extracting from running supervisor
    SUPERVISOR_TOKEN="$(vm_exec "cat /run/secrets/hassio_token 2>/dev/null || echo")" || SUPERVISOR_TOKEN=""
fi
if [[ -z "$SUPERVISOR_TOKEN" ]]; then
    test_warn "SUPERVISOR_TOKEN not set — some tests will be skipped"
    test_info "Set SUPERVISOR_TOKEN=<token> or HA_TOKEN for full Supervisor API access"
else
    test_pass "Supervisor token available"
fi

# --- Supervisor container check ---
test_step "hassio_supervisor container state"
CONTAINER_STATE="$(vm_exec "docker inspect --format='{{.State.Status}}' hassio_supervisor 2>/dev/null || echo missing")"
case "$CONTAINER_STATE" in
    running) test_pass "hassio_supervisor container is running" ;;
    missing) test_warn "hassio_supervisor container not yet created (image still pulling?)" ;;
    *)       test_warn "hassio_supervisor container state: $CONTAINER_STATE" ;;
esac

# --- Supervisor service status ---
test_step "hassio-supervisor systemd service"
SVC_STATUS="$(vm_exec "systemctl is-active hassio-supervisor 2>/dev/null || echo unknown")"
case "$SVC_STATUS" in
    active) test_pass "hassio-supervisor service: active" ;;
    *)      test_warn "hassio-supervisor service: $SVC_STATUS" ;;
esac

# --- Supervisor log check ---
test_step "Supervisor recent journal (last 20 lines)"
JOURNAL="$(vm_exec "journalctl -u hassio-supervisor -n 20 --no-pager 2>/dev/null || echo NO_JOURNAL")"
echo "$JOURNAL" | sed 's/^/    /'
if echo "$JOURNAL" | grep -qi "error\|fatal\|panic"; then
    test_warn "Supervisor journal contains error/fatal messages — review above"
else
    test_pass "No fatal errors in Supervisor journal"
fi

# --- Supervisor API tests (if token available) ---
if [[ -n "$SUPERVISOR_TOKEN" ]]; then
    sup_api() {
        curl -sf --max-time 10 \
            -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
            "$SUPERVISOR_URL/$1" 2>/dev/null || echo '{"result":"error"}'
    }

    test_step "GET /api/hassio/supervisor/info"
    INFO="$(sup_api "supervisor/info")"
    if echo "$INFO" | grep -q '"result":"ok"'; then
        VERSION="$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('version','unknown'))" 2>/dev/null || echo unknown)"
        test_pass "Supervisor version: $VERSION"
    else
        test_warn "Supervisor info: $INFO"
    fi

    test_step "GET /api/hassio/core/info"
    CORE_INFO="$(sup_api "core/info")"
    if echo "$CORE_INFO" | grep -q '"result":"ok"'; then
        CORE_VER="$(echo "$CORE_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('version','unknown'))" 2>/dev/null || echo unknown)"
        test_pass "HA Core version: $CORE_VER"
    else
        test_warn "Core info: $CORE_INFO"
    fi

    test_step "GET /api/hassio/addons (list available add-ons)"
    ADDONS="$(sup_api "addons")"
    if echo "$ADDONS" | grep -q '"result":"ok"'; then
        COUNT="$(echo "$ADDONS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('addons',[])))" 2>/dev/null || echo 0)"
        test_pass "Add-ons available: $COUNT"
    else
        test_warn "Add-ons: $ADDONS"
    fi

    test_step "GET /api/hassio/store (check add-on store)"
    STORE="$(sup_api "store")"
    if echo "$STORE" | grep -q '"result":"ok"'; then
        test_pass "Add-on store is accessible"
    else
        test_warn "Store: $STORE"
    fi
else
    test_info "Skipping Supervisor API tests (no token)"
fi

# --- Docker image pull check ---
test_step "Check Docker images present for Supervisor"
IMAGES="$(vm_exec "docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i 'homeassistant\|hassio' | head -10 || echo NONE")"
if [[ "$IMAGES" == "NONE" || -z "$IMAGES" ]]; then
    test_warn "No HA/hassio Docker images found — Supervisor may still be pulling"
else
    test_pass "HA Docker images present:"
    echo "$IMAGES" | sed 's/^/    /'
fi

test_summary
