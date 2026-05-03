#!/usr/bin/env bash
# Pack the Gentoo chroot (TARGET_ROOT) into a compressed tarball for artifact hand-off.
# Usage: bash rootfs_pack.sh [output_path] [--no-clean-src]
#
# Options:
#   --no-clean-src   Skip 'make clean' on kernel sources (keeps .o files for incremental
#                    re-compilation on the next run of the kernel job).
#
# The tarball intentionally excludes virtual filesystems, temp files, and the portage
# distfiles cache so that successive jobs get a compact, self-contained snapshot.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACK_OUT="/tmp/rootfs.tar.zst"
CLEAN_SRC=true

for arg in "$@"; do
  case "$arg" in
    --no-clean-src) CLEAN_SRC=false ;;
    *)              PACK_OUT="$arg" ;;
  esac
done

require_root

# Install zstd on build host if missing (needed for compression).
if ! command -v zstd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt-get install -y -q zstd >/dev/null
fi
command -v zstd >/dev/null 2>&1 || die "zstd not found; install it before running rootfs_pack.sh"

if $CLEAN_SRC; then
  log "Cleaning kernel build objects in chroot to reduce artifact size"
  for kdir in "$TARGET_ROOT"/usr/src/linux-*; do
    [[ -d "$kdir" ]] || continue
    [[ -f "$kdir/Makefile" ]] || continue
    log "  make clean in $kdir"
    chroot "$TARGET_ROOT" /bin/bash -c \
      "cd '/usr/src/$(basename "$kdir")' && make clean 2>/dev/null" || true
  done
fi

log "Packing $TARGET_ROOT → $PACK_OUT"
mkdir -p "$(dirname "$PACK_OUT")"

# Embed the highest completed stage into a sidecar file next to the tarball
# so any consumer (CI step, next job) can discover the stage without unpacking.
# The sidecar always lives in the same directory as PACK_OUT (default: /tmp).
_META="$(dirname "$PACK_OUT")/rootfs_meta.txt"
if [[ -f "$STATE_ROOT/completed_stage" ]]; then
  _COMPLETED_STAGE="$(cat "$STATE_ROOT/completed_stage")"
  log "Writing completed_stage=$_COMPLETED_STAGE to sidecar $_META"
  printf 'COMPLETED_STAGE=%s\n' "$_COMPLETED_STAGE" > "$_META"
else
  log "No completed_stage marker found; rootfs_meta.txt will be absent"
  rm -f "$_META"
fi
unset _META _COMPLETED_STAGE

tar \
  --use-compress-program='zstd -T0 -3' \
  --exclude="${TARGET_ROOT}/proc" \
  --exclude="${TARGET_ROOT}/sys" \
  --exclude="${TARGET_ROOT}/dev" \
  --exclude="${TARGET_ROOT}/run" \
  --exclude="${TARGET_ROOT}/tmp" \
  --exclude="${TARGET_ROOT}/var/tmp" \
  --exclude="${TARGET_ROOT}/var/cache/distfiles" \
  -cpf "$PACK_OUT" \
  -C "$(dirname "$TARGET_ROOT")" "$(basename "$TARGET_ROOT")"

log "Pack complete: $PACK_OUT ($(du -sh "$PACK_OUT" | cut -f1))"
