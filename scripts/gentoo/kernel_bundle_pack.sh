#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OUT_PATH="${1:-/tmp/kernel-bundle.tar.zst}"

require_root

if ! command -v zstd >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt-get update -y -q >/dev/null
  apt-get install -y -q zstd >/dev/null
fi
command -v zstd >/dev/null 2>&1 || die "zstd not found; install it before running kernel_bundle_pack.sh"

latest_kernel="$(find "$TARGET_ROOT/boot" -maxdepth 1 -type f \( -name 'vmlinuz-*' -o -name 'kernel-*' \) | sort -V | tail -n 1 || true)"
[[ -n "$latest_kernel" ]] || die "No installed kernel found under $TARGET_ROOT/boot"

mkdir -p "$(dirname "$OUT_PATH")"

meta_path="$(dirname "$OUT_PATH")/kernel_bundle_meta.txt"
{
  printf 'KERNEL_IMAGE=%s\n' "$(basename "$latest_kernel")"
  printf 'CREATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$meta_path"

tar \
  --use-compress-program='zstd -T0 -3' \
  -cpf "$OUT_PATH" \
  -C "$TARGET_ROOT" \
  boot \
  lib/modules

log "Kernel bundle written to $OUT_PATH ($(du -sh "$OUT_PATH" | cut -f1))"