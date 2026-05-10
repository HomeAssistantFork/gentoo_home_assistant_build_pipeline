#!/usr/bin/env bash
# Pack TARGET_ROOT into a compressed tarball for job hand-off.
# Usage: bash rootfs_pack.sh [output_path] [--no-clean-src]
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PACK_OUT="/tmp/rootfs.tar.zst"
CLEAN_SRC=true

for arg in "$@"; do
  case "$arg" in
    --no-clean-src) CLEAN_SRC=false ;;
    *) PACK_OUT="$arg" ;;
  esac
done

require_root

if ! command -v zstd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt-get update -y -q >/dev/null
  apt-get install -y -q zstd >/dev/null
fi
command -v zstd >/dev/null 2>&1 || die "zstd not found; install it before running rootfs_pack.sh"

if $CLEAN_SRC; then
  log "Cleaning kernel build objects in chroot to reduce artifact size"
  for kdir in "$TARGET_ROOT"/usr/src/linux-*; do
    [[ -d "$kdir" ]] || continue
    [[ -f "$kdir/Makefile" ]] || continue
    run_in_chroot "cd '/usr/src/$(basename "$kdir")' && make clean 2>/dev/null || true"
  done
fi

log "Packing $TARGET_ROOT -> $PACK_OUT"
mkdir -p "$(dirname "$PACK_OUT")"

_META="$(dirname "$PACK_OUT")/rootfs_meta.txt"
if [[ -f "$STATE_ROOT/completed_stage" ]]; then
  _COMPLETED_STAGE="$(cat "$STATE_ROOT/completed_stage")"
  printf 'COMPLETED_STAGE=%s\n' "$_COMPLETED_STAGE" > "$_META"
  log "Wrote completed_stage=$_COMPLETED_STAGE to $_META"
else
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
