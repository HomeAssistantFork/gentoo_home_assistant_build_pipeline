#!/usr/bin/env bash
set -Eeuo pipefail

artifact_name=""
download_dir=""
workflow_name="Build GentooHA"
branch="${GITHUB_REF_NAME:-}"
run_id=""
repository="${GITHUB_REPOSITORY:-}"

log() { printf '[restore_run_artifact] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-name)
      artifact_name="${2:-}"
      shift 2
      ;;
    --download-dir)
      download_dir="${2:-}"
      shift 2
      ;;
    --workflow-name)
      workflow_name="${2:-}"
      shift 2
      ;;
    --branch)
      branch="${2:-}"
      shift 2
      ;;
    --run-id)
      run_id="${2:-}"
      shift 2
      ;;
    --repository)
      repository="${2:-}"
      shift 2
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$artifact_name" ]] || die "--artifact-name is required"
[[ -n "$download_dir" ]] || die "--download-dir is required"
[[ -n "$repository" ]] || die "Repository not set; pass --repository or set GITHUB_REPOSITORY"

command -v gh >/dev/null 2>&1 || die "gh CLI is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

current_run_id="${GITHUB_RUN_ID:-}"
candidate_runs=()

if [[ -n "$run_id" ]]; then
  candidate_runs+=("$run_id")
else
  [[ -n "$branch" ]] || die "--branch is required when --run-id is omitted"
  log "Searching branch '$branch' for artifact '$artifact_name' in workflow '$workflow_name'"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if [[ -n "$current_run_id" && "$id" == "$current_run_id" ]]; then
      continue
    fi
    candidate_runs+=("$id")
  done < <(
    gh api "repos/$repository/actions/runs?branch=$branch&per_page=100" | \
      jq -r --arg workflow "$workflow_name" '
        .workflow_runs[]
        | select(.name == $workflow)
        | select(.status == "completed")
        | .id
      '
  )
fi

cache_hit="false"
source_run_id=""

for candidate in "${candidate_runs[@]}"; do
  log "Checking run $candidate for artifact '$artifact_name'"
  if gh api "repos/$repository/actions/runs/$candidate/artifacts?per_page=100" | \
      jq -e --arg artifact "$artifact_name" '.artifacts[] | select(.name == $artifact and .expired == false)' >/dev/null; then
    mkdir -p "$download_dir"
    gh run download "$candidate" --repo "$repository" --name "$artifact_name" --dir "$download_dir" >/dev/null
    cache_hit="true"
    source_run_id="$candidate"
    log "Downloaded artifact '$artifact_name' from run $candidate"
    break
  fi
done

if [[ "$cache_hit" != "true" ]]; then
  log "No reusable artifact found for '$artifact_name'"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'cache_hit=%s\n' "$cache_hit"
    printf 'source_run_id=%s\n' "$source_run_id"
  } >> "$GITHUB_OUTPUT"
fi