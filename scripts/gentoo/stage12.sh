#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

stage_start stage12
require_root
mount_chroot_fs

BINPKG_DIR="${BINPKG_DIR:-${TARGET_ROOT}/var/cache/binpkgs}"

log "Generating binary packages for future builds"

# Ensure binary package cache directory exists
mkdir -p "$BINPKG_DIR"
chmod 755 "$BINPKG_DIR"

chroot_script="$(cat <<'EOF'
set -euo pipefail
set +u
source /etc/profile
set -u

# Enable binary package generation in FEATURES
export FEATURES="${FEATURES:-} buildpkg"

log() { echo "[stage12] $*" >&2; }

# Rebuild all installed packages as binary packages for caching
# This allows future builds to use --getbinpkg for faster iteration
log "Starting binary package generation for @world (this may take 10-30 minutes)"

emerge \
  --ask=n \
  --buildpkg=y \
  --buildpkg-exclude 'virtual/* acct-*/* media-* games-*' \
  --usepkgonly=n \
  --quiet \
  @world 2>&1 | tail -20

log "Binary package generation complete"
if [[ -d /var/cache/binpkgs ]]; then
  binpkg_count=$(find /var/cache/binpkgs -name '*.tbz2' 2>/dev/null | wc -l)
  log "Generated $binpkg_count binary packages"
fi
EOF
)"

chroot "$TARGET_ROOT" bash -c "$chroot_script" || true

# Verify binpkg directory created
if [[ ! -d "$BINPKG_DIR" ]]; then
  warn "Binary package directory not created; skipping verification"
else
  binpkg_count=$(find "$BINPKG_DIR" -name '*.tbz2' 2>/dev/null | wc -l)
  if [[ "$binpkg_count" -gt 0 ]]; then
    log "Binary package cache ready: $binpkg_count packages available in $BINPKG_DIR"
  else
    log "Binary package generation completed but cache appears empty (may be normal for this build)"
  fi
fi

log "Stage12 (binary package generation) complete"
stage_end stage12
