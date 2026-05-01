#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for stage in stage1.sh stage2.sh stage3.sh stage4.sh stage5.sh stage6.sh stage7.sh stage8.sh; do
  echo "==== Running ${stage} ===="
  "$SCRIPT_DIR/$stage"
done

echo "All stages completed."
