#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

START_STAGE="${START_STAGE:-1}"
END_STAGE="${END_STAGE:-10}"

ALL_STAGES=(stage1 stage2 stage3 stage4 stage5 stage6 stage7 stage8 stage9 stage10)

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
