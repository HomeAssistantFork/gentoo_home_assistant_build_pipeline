#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_ROOT="${ROOT_DIR}/repos/home-assistant"
CLONE_SCRIPT="${ROOT_DIR}/scripts/repos/clone_home_assistant_org.sh"

log() { printf '[configure] %s\n' "$*"; }
die() { printf '[configure] ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

has_submodule_config() {
  [[ -f "${ROOT_DIR}/.gitmodules" ]] || return 1
  git -C "$ROOT_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | grep -q ' repos/'
}

ensure_fork_remotes() {
  local repo path

  declare -A fork_urls=(
    [version]="https://github.com/HomeAssistantFork/version.git"
    [operating-system]="https://github.com/HomeAssistantFork/operating-system.git"
    [buildroot]="https://github.com/HomeAssistantFork/buildroot.git"
    [brands]="https://github.com/HomeAssistantFork/brands.git"
    [android]="https://github.com/HomeAssistantFork/android.git"
    [addons]="https://github.com/HomeAssistantFork/addons.git"
  )

  mkdir -p "$REPOS_ROOT"

  for repo in "${!fork_urls[@]}"; do
    path="${REPOS_ROOT}/${repo}"

    if [[ ! -d "${path}/.git" ]]; then
      log "Repo ${repo} is missing; cloning from upstream first"
      git clone "https://github.com/home-assistant/${repo}.git" "$path"
    fi

    git -C "$path" remote set-url origin "${fork_urls[$repo]}"

    if git -C "$path" remote get-url upstream >/dev/null 2>&1; then
      git -C "$path" remote set-url upstream "https://github.com/home-assistant/${repo}.git"
    else
      git -C "$path" remote add upstream "https://github.com/home-assistant/${repo}.git"
    fi

    log "Configured ${repo}: origin -> ${fork_urls[$repo]}"
  done
}

normalize_windows_submodule_worktrees() {
  local repo path os_name

  os_name="$(uname -s 2>/dev/null || true)"
  case "$os_name" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
      return 0
      ;;
  esac

  log "Normalizing Windows submodule worktrees for clean status"
  for repo in addons android brands buildroot operating-system version; do
    path="${REPOS_ROOT}/${repo}"
    [[ -d "${path}/.git" ]] || continue
    git -C "$path" config core.symlinks false
    git -C "$path" reset --hard HEAD >/dev/null 2>&1 || true
    git -C "$path" clean -fd >/dev/null 2>&1 || true
    log "Normalized ${repo}"
  done
}

main() {
  require_cmd git

  log "Root: ${ROOT_DIR}"

  if has_submodule_config; then
    log "Detected submodule configuration under repos/. Restoring submodules."
    git -C "$ROOT_DIR" submodule sync --recursive
    git -C "$ROOT_DIR" submodule update --init --recursive
  else
    log "No repos submodule configuration found. Using clone/resume fallback."
    [[ -x "$CLONE_SCRIPT" ]] || die "Clone script not found or not executable: ${CLONE_SCRIPT}"

    (
      cd "$ROOT_DIR"
      SHALLOW="${SHALLOW:-true}" \
      RESUME="${RESUME:-true}" \
      INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-false}" \
      bash "$CLONE_SCRIPT"
    )
  fi

  ensure_fork_remotes
  normalize_windows_submodule_worktrees

  log "Done. Repos are configured."
}

main "$@"
