#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage13
require_root

ARTIFACT_DIR="${ARTIFACT_DIR:-/var/lib/ha-gentoo-hybrid/artifacts}"
mkdir -p "$ARTIFACT_DIR"

MANIFEST="$ARTIFACT_DIR/gentooha-${PLATFORM}-${FLAVOR}.manifest.txt"
log "Generating artifact manifest: $MANIFEST"

shopt -s nullglob
artifacts=("$ARTIFACT_DIR"/gentooha-"$PLATFORM"-"$FLAVOR".*)
shopt -u nullglob

# Exclude any previous manifest files from the artifact list/checksum set.
filtered=()
for f in "${artifacts[@]}"; do
  [[ "$f" == *.manifest.txt ]] && continue
  filtered+=("$f")
done

(( ${#filtered[@]} > 0 )) || die "No artifacts found for ${PLATFORM}/${FLAVOR} in $ARTIFACT_DIR. Stage11 must run before stage13."

{
  echo "platform=$PLATFORM"
  echo "flavor=$FLAVOR"
  echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -f "$STATE_ROOT/completed_stage" ]]; then
    echo "completed_stage=$(cat "$STATE_ROOT/completed_stage")"
  fi
  echo ""
  echo "artifacts:"
  for f in "${filtered[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo "sha256:"
  for f in "${filtered[@]}"; do
    sha256sum "$f"
  done
} > "$MANIFEST"

log "Manifest written: $MANIFEST"
stage_end stage13
