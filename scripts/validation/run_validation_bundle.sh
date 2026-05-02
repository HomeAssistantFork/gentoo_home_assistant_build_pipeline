#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ARTIFACT_ROOT="${ARTIFACT_ROOT:-$ROOT_DIR/artifacts/validation}"
KERNEL_TRACK="${KERNEL_TRACK:-unknown}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$ARTIFACT_ROOT/$STAMP-$KERNEL_TRACK"

mkdir -p "$OUT_DIR"

run_and_capture() {
  local name="$1"
  shift
  local out="$OUT_DIR/$name.log"
  if "$@" >"$out" 2>&1; then
    printf '[PASS] %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name"
    return 1
  fi
}

{
  echo "timestamp_utc=$STAMP"
  echo "kernel_track=$KERNEL_TRACK"
  echo "uname=$(uname -a)"
  echo "systemd_state=$(systemctl is-system-running || true)"
} >"$OUT_DIR/metadata.txt"

run_and_capture preflight "$ROOT_DIR/scripts/compat/preflight_ha_supervisor.sh"
run_and_capture stack_validation "$ROOT_DIR/scripts/validation/validate_ha_stack.sh"

if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
  echo "nodered_lifecycle=attempted" >>"$OUT_DIR/metadata.txt"
else
  echo "nodered_lifecycle=skipped_no_token" >>"$OUT_DIR/metadata.txt"
fi

# Record key runtime states for post-mortem analysis.
(systemctl status docker --no-pager -l || true) >"$OUT_DIR/docker.status.log" 2>&1
(systemctl status hassio-supervisor --no-pager -l || true) >"$OUT_DIR/hassio-supervisor.status.log" 2>&1
(journalctl -u docker -n 120 --no-pager || true) >"$OUT_DIR/docker.journal.log" 2>&1
(journalctl -u hassio-supervisor -n 120 --no-pager || true) >"$OUT_DIR/hassio-supervisor.journal.log" 2>&1

BUNDLE_PATH="$ARTIFACT_ROOT/$STAMP-$KERNEL_TRACK.tar.gz"
tar -C "$ARTIFACT_ROOT" -czf "$BUNDLE_PATH" "$(basename "$OUT_DIR")"

echo "Validation bundle created: $BUNDLE_PATH"
