#!/usr/bin/env bash
set -Eeuo pipefail

ORG="home-assistant"
OUT_DIR="${OUT_DIR:-$PWD/repos/home-assistant}"
MANIFEST_DIR="${MANIFEST_DIR:-$PWD/manifests}"
MANIFEST_FILE="${MANIFEST_FILE:-$MANIFEST_DIR/home-assistant-repos.jsonl}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-false}"
SHALLOW="${SHALLOW:-true}"
RESUME="${RESUME:-true}"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-3}"
PRIORITY_REPOS="supervisor operating-system core"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

retry() {
  local n=1
  local max="$RETRY_COUNT"
  local delay="$RETRY_DELAY"
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "$n" -ge "$max" ]]; then
      return 1
    fi
    log "Retry $n/$max failed for: $*"
    sleep "$delay"
    n=$((n + 1))
  done
}

get_page() {
  local page="$1"
  local curl_args=(
    -fsSL
    -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28'
  )
  if [[ -n "$GITHUB_TOKEN" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  retry curl "${curl_args[@]}" "https://api.github.com/orgs/${ORG}/repos?per_page=100&page=${page}&type=public"
}

clone_or_update_repo() {
  local name="$1"
  local clone_url="$2"
  local archived="$3"
  local target_dir="$OUT_DIR/$name"

  if [[ "$INCLUDE_ARCHIVED" != "true" && "$archived" == "true" ]]; then
    log "Skipping archived repo: $name"
    return 0
  fi

  if [[ -d "$target_dir/.git" ]]; then
    if [[ "$RESUME" == "true" ]]; then
      log "Updating existing repo: $name"
      retry git -C "$target_dir" fetch --all --tags --prune >/dev/null
      return 0
    fi
    die "Repo already exists and RESUME=false: $name"
  fi

  local depth_args=()
  if [[ "$SHALLOW" == "true" ]]; then
    depth_args=(--depth 1)
  fi

  log "Cloning: $name"
  retry git clone "${depth_args[@]}" "$clone_url" "$target_dir" >/dev/null
}

main() {
  require_cmd curl
  require_cmd jq
  require_cmd git

  mkdir -p "$OUT_DIR" "$MANIFEST_DIR"
  : > "$MANIFEST_FILE"

  local tmp_all
  tmp_all="$(mktemp)"

  local page=1
  while true; do
    log "Fetching org repo page $page"
    local payload
    payload="$(get_page "$page")"

    local count
    count="$(jq 'length' <<<"$payload")"
    if [[ "$count" -eq 0 ]]; then
      break
    fi

    jq -r '.[] | @base64' <<<"$payload" >> "$tmp_all"
    page=$((page + 1))
  done

  while read -r priority; do
    [[ -z "$priority" ]] && continue
    local rec
    rec="$(grep -m1 "$priority" "$tmp_all" || true)"
    if [[ -n "$rec" ]]; then
      local decoded
      decoded="$(printf '%s' "$rec" | base64 -d)"
      local name clone_url archived
      name="$(jq -r '.name' <<<"$decoded")"
      clone_url="$(jq -r '.clone_url' <<<"$decoded")"
      archived="$(jq -r '.archived' <<<"$decoded")"
      clone_or_update_repo "$name" "$clone_url" "$archived"
      jq -nc --arg name "$name" --arg phase "priority" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp:$ts,repo:$name,phase:$phase,status:"ok"}' >> "$MANIFEST_FILE"
    fi
  done < <(printf '%s\n' $PRIORITY_REPOS)

  while read -r encoded; do
    [[ -z "$encoded" ]] && continue
    local obj name clone_url archived
    obj="$(printf '%s' "$encoded" | base64 -d)"
    name="$(jq -r '.name' <<<"$obj")"
    clone_url="$(jq -r '.clone_url' <<<"$obj")"
    archived="$(jq -r '.archived' <<<"$obj")"

    case " $PRIORITY_REPOS " in
      *" $name "*) continue ;;
    esac

    if clone_or_update_repo "$name" "$clone_url" "$archived"; then
      jq -nc --arg name "$name" --arg phase "bulk" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp:$ts,repo:$name,phase:$phase,status:"ok"}' >> "$MANIFEST_FILE"
    else
      jq -nc --arg name "$name" --arg phase "bulk" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp:$ts,repo:$name,phase:$phase,status:"error"}' >> "$MANIFEST_FILE"
    fi
  done < "$tmp_all"

  rm -f "$tmp_all"
  log "Done. Manifest: $MANIFEST_FILE"
}

main "$@"
