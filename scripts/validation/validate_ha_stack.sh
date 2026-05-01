#!/usr/bin/env bash
set -Eeuo pipefail

HA_URL="${HA_URL:-http://127.0.0.1:8123}"
SUPERVISOR_URL="${SUPERVISOR_URL:-http://supervisor}"
SUPERVISOR_TOKEN="${SUPERVISOR_TOKEN:-}"

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
  curl -fsS \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$SUPERVISOR_URL/addons/core_nodered/install" >/dev/null || fail "Node-RED install API call failed"
  pass "Node-RED install API call succeeded"
else
  echo "[WARN] SUPERVISOR_TOKEN not set. Skipping Node-RED API validation."
fi

echo "Validation complete."
