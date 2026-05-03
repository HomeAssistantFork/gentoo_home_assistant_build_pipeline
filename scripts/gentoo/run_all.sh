#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

START_STAGE="${START_STAGE:-1}"
END_STAGE="${END_STAGE:-10}"

ALL_STAGES=(stage1 stage2 stage3 stage4 stage5 stage6 stage7 stage8 stage9 stage10)

# Auto-advance START_STAGE based on the completed_stage marker written by
# stage_end() and preserved inside the rootfs across pack/unpack cycles.
# This lets each job skip stages already finished in a prior job without
# needing the caller to set START_STAGE correctly.
_MANIFEST="$STATE_ROOT/completed_stage"
if [[ -f "$_MANIFEST" ]]; then
  _COMPLETED="$(cat "$_MANIFEST")"
  _AUTO_START=$(( _COMPLETED + 1 ))
  if [[ "$_AUTO_START" -gt "$START_STAGE" ]]; then
    log "completed_stage manifest reports stage $_COMPLETED done; advancing START_STAGE $START_STAGE → $_AUTO_START"
    START_STAGE="$_AUTO_START"
  fi
fi
unset _MANIFEST _COMPLETED _AUTO_START

log "Build config: PLATFORM=$PLATFORM FLAVOR=$FLAVOR ARCH=$ARCH START_STAGE=$START_STAGE END_STAGE=$END_STAGE"

for stage in "${ALL_STAGES[@]}"; do
  stage_num="${stage#stage}"
  if [[ "$stage_num" -lt "$START_STAGE" ]]; then
    log "Skipping ${stage} (before START_STAGE=$START_STAGE)"
    continue
  fi
  if [[ "$stage_num" -gt "$END_STAGE" ]]; then
    log "Stopping after END_STAGE=$END_STAGE"
    break
  fi
  echo "==== Running ${stage}.sh ===="
  bash "$SCRIPT_DIR/${stage}.sh"
done

log "Stages ${START_STAGE}–${END_STAGE} complete. PLATFORM=$PLATFORM FLAVOR=$FLAVOR"
