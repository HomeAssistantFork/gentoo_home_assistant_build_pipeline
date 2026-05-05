#!/usr/bin/env bash
# common_test.sh — Shared helpers for GentooHA test scripts.
# Source this from other test scripts: source "$(dirname "$0")/common_test.sh"
set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

test_header() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD} $1${NC}"
    echo -e "${BOLD}============================================================${NC}"
}

test_step() {
    echo -e "\n${BLUE}  >> $1${NC}"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED+1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED+1))
    echo -e "  ${RED}[FAIL]${NC} $1"
    test_summary
    exit 1
}

test_warn() {
    TESTS_WARNED=$((TESTS_WARNED+1))
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

test_info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
}

test_summary() {
    echo ""
    echo -e "${BOLD}------------------------------------------------------------${NC}"
    echo -e "${BOLD} Results: ${GREEN}${TESTS_PASSED} passed${NC}  ${RED}${TESTS_FAILED} failed${NC}  ${YELLOW}${TESTS_WARNED} warnings${NC}"
    echo -e "${BOLD}------------------------------------------------------------${NC}"
    [[ $TESTS_FAILED -eq 0 ]]
}

# Run a command inside the GentooHA VM via VBoxManage or via WSL if local
run_in_vm() {
    local cmd="$1"
    local vm_name="${VM_NAME:-GentooHA 1}"
    local vbm="${VBOXMANAGE:-VBoxManage}"

    if command -v "$vbm" &>/dev/null || [[ -f "$vbm" ]]; then
        "$vbm" guestcontrol "$vm_name" run --exe /bin/bash \
            --username root --password "" \
            -- bash -c "$cmd" 2>/dev/null
    else
        # Fallback: WSL direct if GentooHA distro is available
        wsl -d GentooHA -- bash -c "$cmd" 2>/dev/null
    fi
}

# Curl the HA API with optional token
ha_api() {
    local path="$1"
    local token="${HA_TOKEN:-}"
    local base="${HA_BASE_URL:-http://localhost:8123}"
    if [[ -n "$token" ]]; then
        curl -sf --max-time 10 -H "Authorization: Bearer $token" "${base}${path}"
    else
        curl -sf --max-time 10 "${base}${path}"
    fi
}

# Check if HA API responds at all
ha_api_available() {
    curl -sf --max-time 5 "${HA_BASE_URL:-http://localhost:8123}/api/" &>/dev/null
}
