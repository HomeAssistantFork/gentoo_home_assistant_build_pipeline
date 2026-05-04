#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

START_STAGE="${START_STAGE:-1}"

ALL_STAGES=(stage1 stage2 stage3 stage4 stage5 stage6 stage7 stage8 stage9 stage10 stage11)

log "Build config: PLATFORM=$PLATFORM FLAVOR=$FLAVOR ARCH=$ARCH START_STAGE=$START_STAGE"

for stage in "${ALL_STAGES[@]}"; do
  stage_num="${stage#stage}"
  if [[ "$stage_num" -lt "$START_STAGE" ]]; then
    log "Skipping ${stage} (START_STAGE=$START_STAGE)"
    continue
  fi
  echo "==== Running ${stage}.sh ===="
  bash "$SCRIPT_DIR/${stage}.sh"
done

log "All stages completed. PLATFORM=$PLATFORM FLAVOR=$FLAVOR artifact: gentooha-${PLATFORM}-${FLAVOR}.${ARTIFACT_EXT}"
