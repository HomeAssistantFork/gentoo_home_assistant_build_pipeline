#!/usr/bin/env bash
# test_ha_api.sh — Test Home Assistant HTTP API availability and basic responses.
# Usage: bash scripts/tests/ai/test_ha_api.sh [BASE_URL] [HA_TOKEN]
# BASE_URL defaults to http://localhost:8123
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_test.sh"

export HA_BASE_URL="${1:-${HA_BASE_URL:-http://localhost:8123}}"
export HA_TOKEN="${2:-${HA_TOKEN:-}}"

test_header "Home Assistant API Tests: $HA_BASE_URL"

# --- Connectivity ---
test_step "Reach HA HTTP port (no auth required)"
HTTP_CODE="$(curl -o /dev/null -sw '%{http_code}' --max-time 10 "$HA_BASE_URL/" 2>/dev/null || echo 000)"
case "$HTTP_CODE" in
    200|302|301) test_pass "HTTP $HTTP_CODE — HA frontend reachable" ;;
    401)         test_pass "HTTP 401 — HA is up (auth required, expected)" ;;
    000)         test_fail "Cannot reach $HA_BASE_URL — VM may not be running or port not forwarded" ;;
    *)           test_warn "HTTP $HTTP_CODE — unexpected response from HA" ;;
esac

# --- API root (no auth) ---
test_step "GET /api/ (expects 401 without token or 200 with token)"
API_CODE="$(curl -o /dev/null -sw '%{http_code}' --max-time 10 "$HA_BASE_URL/api/" 2>/dev/null || echo 000)"
case "$API_CODE" in
    200) test_pass "API root returned 200 (open access or valid token)" ;;
    401) test_pass "API root returned 401 (auth required — correct behavior)" ;;
    *)   test_warn "API root returned $API_CODE" ;;
esac

# --- API with token (if provided) ---
if [[ -n "$HA_TOKEN" ]]; then
    test_step "GET /api/ with Bearer token"
    API_BODY="$(curl -sf --max-time 10 \
        -H "Authorization: Bearer $HA_TOKEN" \
        "$HA_BASE_URL/api/" 2>/dev/null || echo FAILED)"
    if [[ "$API_BODY" == *"message"* ]]; then
        test_pass "API returned message: $API_BODY"
    else
        test_warn "API response with token: $API_BODY"
    fi

    # --- Config ---
    test_step "GET /api/config"
    CONFIG="$(curl -sf --max-time 10 \
        -H "Authorization: Bearer $HA_TOKEN" \
        "$HA_BASE_URL/api/config" 2>/dev/null || echo FAILED)"
    if [[ "$CONFIG" == *"version"* ]]; then
        VERSION="$(echo "$CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null || echo unknown)"
        test_pass "HA version: $VERSION"
    else
        test_warn "Config API response: $CONFIG"
    fi

    # --- States ---
    test_step "GET /api/states"
    STATES="$(curl -sf --max-time 10 \
        -H "Authorization: Bearer $HA_TOKEN" \
        "$HA_BASE_URL/api/states" 2>/dev/null || echo FAILED)"
    if [[ "$STATES" == "["* ]]; then
        COUNT="$(echo "$STATES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo unknown)"
        test_pass "States count: $COUNT"
    else
        test_warn "States API: $STATES"
    fi

    # --- Supervisor info ---
    test_step "GET /api/hassio/supervisor/info"
    SUP_INFO="$(curl -sf --max-time 10 \
        -H "Authorization: Bearer $HA_TOKEN" \
        -H "X-Hassio-Key: $HA_TOKEN" \
        "$HA_BASE_URL/api/hassio/supervisor/info" 2>/dev/null || echo FAILED)"
    if [[ "$SUP_INFO" == *"result"* ]]; then
        test_pass "Supervisor info API responded"
    else
        test_warn "Supervisor info: $SUP_INFO"
    fi
else
    test_info "HA_TOKEN not set — skipping authenticated API tests"
    test_info "Set HA_TOKEN=<long-lived-access-token> to enable full API checks"
fi

# --- Frontend static assets ---
test_step "Frontend static JS served"
JS_CODE="$(curl -o /dev/null -sw '%{http_code}' --max-time 10 "$HA_BASE_URL/frontend_latest/" 2>/dev/null || echo 000)"
case "$JS_CODE" in
    200|301|302|403|404) test_pass "Frontend path responds (HTTP $JS_CODE)" ;;
    000) test_warn "Frontend path unreachable" ;;
    *)   test_warn "Frontend path HTTP $JS_CODE" ;;
esac

test_summary
