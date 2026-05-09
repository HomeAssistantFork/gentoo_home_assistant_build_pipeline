#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

START_STAGE="${START_STAGE:-1}"
END_STAGE="${END_STAGE:-12}"

ALL_STAGES=(stage1 stage2 stage3 stage4 stage5 stage6 stage7 stage8 stage9 stage10 stage11 stage12)

_MANIFEST="$STATE_ROOT/completed_stage"
if [[ -f "$_MANIFEST" ]]; then
  _COMPLETED="$(cat "$_MANIFEST" 2>/dev/null || echo 0)"
  if [[ "$_COMPLETED" =~ ^[0-9]+$ ]]; then
    _AUTO_START=$(( _COMPLETED + 1 ))
    if [[ "$_AUTO_START" -gt "$START_STAGE" ]]; then
      log "completed_stage manifest reports stage $_COMPLETED done; advancing START_STAGE $START_STAGE -> $_AUTO_START"
      START_STAGE="$_AUTO_START"
    fi
  fi
fi
unset _MANIFEST _COMPLETED _AUTO_START

# If finalization is requested but artifacts are missing, force stage11 first.
if [[ "$END_STAGE" -ge 12 && "$START_STAGE" -gt 11 ]]; then
  _artifact_dir="${ARTIFACT_DIR:-/var/lib/ha-gentoo-hybrid/artifacts}"
  _artifact_glob="$_artifact_dir/gentooha-${PLATFORM}-${FLAVOR}.*"
  if ! compgen -G "$_artifact_glob" >/dev/null; then
    log "No artifacts found for ${PLATFORM}/${FLAVOR} in $_artifact_dir; forcing START_STAGE=11 before stage12."
    START_STAGE=11
  fi
  unset _artifact_dir _artifact_glob
fi

log "Build config: PLATFORM=$PLATFORM FLAVOR=$FLAVOR ARCH=$ARCH START_STAGE=$START_STAGE END_STAGE=$END_STAGE"

for stage in "${ALL_STAGES[@]}"; do
  stage_num="${stage#stage}"
  if [[ "$stage_num" -lt "$START_STAGE" ]]; then
    log "Skipping ${stage} (START_STAGE=$START_STAGE)"
    continue
  fi
  if [[ "$stage_num" -gt "$END_STAGE" ]]; then
    log "Stopping after END_STAGE=$END_STAGE"
    break
  fi
  echo "==== Running ${stage}.sh ===="
  bash "$SCRIPT_DIR/${stage}.sh"
done

if [[ "$PLATFORM" == "x64" ]]; then
  log "Stages ${START_STAGE}-${END_STAGE} complete. PLATFORM=$PLATFORM FLAVOR=$FLAVOR artifacts: ${X64_ARTIFACT_FORMATS:-${X64_ARTIFACT_FORMAT:-vdi}}"
else
  log "Stages ${START_STAGE}-${END_STAGE} complete. PLATFORM=$PLATFORM FLAVOR=$FLAVOR artifact: gentooha-${PLATFORM}-${FLAVOR}.${ARTIFACT_EXT}"
fi
