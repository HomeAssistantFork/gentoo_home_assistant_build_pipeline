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

_ROOT_PARENT="$(dirname "$TARGET_ROOT")"
_ROOT_NAME="$(basename "$TARGET_ROOT")"

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
  --one-file-system \
  --use-compress-program='zstd -T0 -3' \
  --exclude="${_ROOT_NAME}/proc" \
  --exclude="${_ROOT_NAME}/proc/**" \
  --exclude="${_ROOT_NAME}/sys" \
  --exclude="${_ROOT_NAME}/sys/**" \
  --exclude="${_ROOT_NAME}/dev" \
  --exclude="${_ROOT_NAME}/dev/**" \
  --exclude="${_ROOT_NAME}/run" \
  --exclude="${_ROOT_NAME}/run/**" \
  --exclude="${_ROOT_NAME}/tmp" \
  --exclude="${_ROOT_NAME}/tmp/**" \
  --exclude="${_ROOT_NAME}/var/tmp" \
  --exclude="${_ROOT_NAME}/var/tmp/**" \
  --exclude="${_ROOT_NAME}/var/cache/distfiles" \
  --exclude="${_ROOT_NAME}/var/cache/distfiles/**" \
  -cpf "$PACK_OUT" \
  -C "$_ROOT_PARENT" "$_ROOT_NAME"

unset _ROOT_PARENT _ROOT_NAME

log "Pack complete: $PACK_OUT ($(du -sh "$PACK_OUT" | cut -f1))"
