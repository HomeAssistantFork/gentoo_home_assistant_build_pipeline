#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage12
require_root

ARTIFACT_DIR="${ARTIFACT_DIR:-/var/lib/ha-gentoo-hybrid/artifacts}"
mkdir -p "$ARTIFACT_DIR"

MANIFEST="$ARTIFACT_DIR/gentooha-${PLATFORM}-${FLAVOR}.manifest.txt"
log "Generating artifact manifest: $MANIFEST"

{
  echo "platform=$PLATFORM"
  echo "flavor=$FLAVOR"
  echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -f "$STATE_ROOT/completed_stage" ]]; then
    echo "completed_stage=$(cat "$STATE_ROOT/completed_stage")"
  fi
  echo ""
  echo "artifacts:"
  ls -1 "$ARTIFACT_DIR"/gentooha-"$PLATFORM"-"$FLAVOR".* 2>/dev/null | sed 's/^/  - /' || true
  echo ""
  echo "sha256:"
  for f in "$ARTIFACT_DIR"/gentooha-"$PLATFORM"-"$FLAVOR".*; do
    [[ -f "$f" ]] || continue
    sha256sum "$f"
  done
} > "$MANIFEST"

log "Manifest written: $MANIFEST"
stage_end stage12
