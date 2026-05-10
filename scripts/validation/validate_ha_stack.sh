#!/usr/bin/env bash
set -Eeuo pipefail

HA_URL="${HA_URL:-http://127.0.0.1:8123}"
SUPERVISOR_URL="${SUPERVISOR_URL:-http://supervisor}"
SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN:-}"
REQUIRE_NODERED_TEST="${REQUIRE_NODERED_TEST:-false}"

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v docker >/dev/null 2>&1 || fail "docker is required"

systemctl is-active --quiet docker || fail "docker service is not active"
pass "docker service is active"

docker ps --format '{{.Names}}' | grep -qi supervisor || fail "Supervisor container not running"
pass "Supervisor container running"

curl -fsS "$HA_URL" >/dev/null || fail "Home Assistant UI endpoint not reachable at $HA_URL"
pass "Home Assistant UI reachable"

if [[ -n "$SUPERVISOR_TOKEN" ]]; then
  api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    if [[ -n "$body" ]]; then
      curl -fsS \
        -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
        -H "Content-Type: application/json" \
        -X "$method" "$SUPERVISOR_URL$path" \
        -d "$body" >/dev/null
    else
      curl -fsS \
        -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
        -H "Content-Type: application/json" \
        -X "$method" "$SUPERVISOR_URL$path" >/dev/null
    fi
  }

  # Node-RED lifecycle: install -> start -> restart -> update.
  api POST "/addons/core_nodered/install" || fail "Node-RED install API call failed"
  pass "Node-RED install API call succeeded"

  api POST "/addons/core_nodered/start" || fail "Node-RED start API call failed"
  pass "Node-RED start API call succeeded"

  api POST "/addons/core_nodered/restart" || fail "Node-RED restart API call failed"
  pass "Node-RED restart API call succeeded"

  api POST "/addons/core_nodered/update" || fail "Node-RED update API call failed"
  pass "Node-RED update API call succeeded"

  api GET "/addons/core_nodered/info" || fail "Node-RED info API call failed"
  pass "Node-RED info API call succeeded"
else
  if [[ "$REQUIRE_NODERED_TEST" == "true" ]]; then
    fail "SUPERVISOR_TOKEN not set and REQUIRE_NODERED_TEST=true. Node-RED lifecycle test is required."
  fi
  echo "[WARN] SUPERVISOR_TOKEN not set. Skipping Node-RED lifecycle validation."
fi

echo "Validation complete."
