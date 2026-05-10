#!/usr/bin/env bash
# test_ha_core.sh — Run Home Assistant core pytest suite against the cloned HA core repo.
# Tests are run on the HOST (not inside the VM) since they are unit/integration tests
# that test HA Python code, not a live deployment.
# Usage: bash scripts/tests/ai/test_ha_core.sh [TEST_PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/common_test.sh"

HA_CORE="$REPO_ROOT/repos/home-assistant/core"
TEST_PATH="${1:-tests/}"
PYTEST_ARGS="${PYTEST_ARGS:--x -q --timeout=60}"

test_header "Home Assistant Core Unit Tests"

# --- Prerequisites ---
test_step "Check HA core repo exists"
if [[ ! -d "$HA_CORE" ]]; then
    test_fail "HA core repo not found at $HA_CORE. Run configure.sh first."
fi
test_pass "Found $HA_CORE"

test_step "Check Python 3 available"
PY="$(command -v python3 2>/dev/null || echo "")"
if [[ -z "$PY" ]]; then
    test_fail "python3 not found. Install Python 3.12+ to run HA tests."
fi
PY_VER="$("$PY" --version 2>&1)"
test_pass "$PY_VER"

test_step "Check pytest available"
PYTEST="$(command -v pytest 2>/dev/null || python3 -m pytest --version &>/dev/null && echo "python3 -m pytest" || echo "")"
if [[ -z "$PYTEST" ]]; then
    test_info "pytest not found — attempting install from requirements_test_all.txt"
    pip3 install -q pytest pytest-asyncio pytest-timeout 2>/dev/null || true
    PYTEST="python3 -m pytest"
fi
PYTEST_VER="$($PYTEST --version 2>&1 | head -1)"
test_pass "$PYTEST_VER"

test_step "Install HA test requirements (may take a few minutes on first run)"
cd "$HA_CORE"
if [[ -f "requirements_test_all.txt" ]]; then
    pip3 install -q -r requirements_test_all.txt 2>/dev/null || \
        test_warn "Some requirements failed to install — tests may skip"
fi

if [[ -f "pyproject.toml" ]]; then
    pip3 install -q -e ".[test]" 2>/dev/null || \
        pip3 install -q -e . 2>/dev/null || \
        test_warn "Editable install failed — some tests may not run"
fi
test_pass "Requirements ready"

# --- Run a smoke subset first ---
test_step "Run smoke test subset (tests/test_config.py or similar)"
SMOKE_TARGET=""
for candidate in \
    "tests/test_config.py" \
    "tests/test_util" \
    "tests/helpers/test_entity.py"; do
    if [[ -e "$HA_CORE/$candidate" ]]; then
        SMOKE_TARGET="$candidate"
        break
    fi
done

if [[ -n "$SMOKE_TARGET" ]]; then
    test_info "Running: $PYTEST $SMOKE_TARGET $PYTEST_ARGS"
    if $PYTEST "$SMOKE_TARGET" $PYTEST_ARGS 2>&1 | tee /tmp/ha_smoke_test.log | tail -20; then
        test_pass "Smoke tests passed"
    else
        test_warn "Smoke tests had failures — see /tmp/ha_smoke_test.log"
    fi
else
    test_warn "No known smoke test file found — skipping smoke subset"
fi

# --- Full test run ---
test_step "Run full test suite: $TEST_PATH (this may take a long time)"
test_info "Running: $PYTEST $TEST_PATH $PYTEST_ARGS"
if $PYTEST "$TEST_PATH" $PYTEST_ARGS 2>&1 | tee /tmp/ha_full_test.log | tail -40; then
    test_pass "Full test suite passed"
else
    FAILURES="$(grep -c 'FAILED' /tmp/ha_full_test.log 2>/dev/null || echo 0)"
    test_warn "Test suite had $FAILURES failures — see /tmp/ha_full_test.log"
    TESTS_FAILED=$((TESTS_FAILED+1))
fi

test_summary
