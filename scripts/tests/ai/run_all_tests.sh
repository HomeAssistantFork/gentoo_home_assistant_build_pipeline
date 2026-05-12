#!/usr/bin/env bash
# run_all_tests.sh — Orchestrate all GentooHA test scripts in correct order.
# Usage:
#   bash scripts/tests/ai/run_all_tests.sh [VM_NAME] [VDI_PATH]
#   SKIP_BOOT=true bash scripts/tests/ai/run_all_tests.sh   (skip boot if VM already running)
#   HA_TOKEN=<tok> bash scripts/tests/ai/run_all_tests.sh   (enable full API tests)
#   SKIP_HA_CORE=true bash scripts/tests/ai/run_all_tests.sh (skip host pytest suite)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

VM_NAME="${1:-GentooHA 1}"
VDI_PATH="${2:-$REPO_ROOT/artifacts/gentooha-x64-debug.vdi}"
SKIP_BOOT="${SKIP_BOOT:-false}"
SKIP_HA_CORE="${SKIP_HA_CORE:-true}"   # off by default; set SKIP_HA_CORE=false to enable
HA_TOKEN="${HA_TOKEN:-}"
SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN:-}"

OVERALL_PASS=0
OVERALL_FAIL=0

run_test() {
    local label="$1"
    local script="$2"
    shift 2
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Running: $label"
    echo "╚══════════════════════════════════════════════════════════════╝"
    if bash "$SCRIPT_DIR/$script" "$@"; then
        OVERALL_PASS=$((OVERALL_PASS+1))
        echo "  ✔ $label PASSED"
    else
        OVERALL_FAIL=$((OVERALL_FAIL+1))
        echo "  ✘ $label FAILED"
    fi
}

# --- 1. Boot ---
if [[ "$SKIP_BOOT" != "true" ]]; then
    run_test "VM Boot" "test_boot.sh" "$VDI_PATH" "$VM_NAME"
else
    echo "[SKIP] Boot test skipped (SKIP_BOOT=true)"
fi

# --- 2. Services ---
run_test "Service Health" "test_services.sh" "$VM_NAME"

# --- 3. HA API ---
run_test "Home Assistant API" "test_ha_api.sh" "http://localhost:8123" "$HA_TOKEN"

# --- 4. Supervisor ---
SUPERVISOR_TOKEN="$SUPERVISOR_TOKEN" run_test "Supervisor" "test_supervisor.sh" "$SUPERVISOR_TOKEN"

# --- 5. HA Core pytest (optional) ---
if [[ "$SKIP_HA_CORE" != "true" ]]; then
    run_test "HA Core Unit Tests" "test_ha_core.sh"
else
    echo ""
    echo "[SKIP] HA Core pytest skipped (set SKIP_HA_CORE=false to enable)"
fi

# --- Summary ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OVERALL RESULTS"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Test suites passed : $OVERALL_PASS"
echo "  Test suites failed : $OVERALL_FAIL"
echo ""
if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo "  ALL TESTS PASSED ✔"
    exit 0
else
    echo "  SOME TESTS FAILED ✘"
    exit 1
fi
