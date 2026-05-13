#!/usr/bin/env bash
set -euo pipefail
cd /mnt/c/Users/tamus/projects/linux/home_assistant_1
rm -f /var/lib/ha-gentoo-hybrid/state/stage6.done /var/lib/ha-gentoo-hybrid/state/stage7.done /var/lib/ha-gentoo-hybrid/state/stage8.done /var/lib/ha-gentoo-hybrid/state/stage9.done /var/lib/ha-gentoo-hybrid/state/stage10.done /var/lib/ha-gentoo-hybrid/state/stage11.done
PLATFORM=x64 FLAVOR=debug START_STAGE=6 END_STAGE=11 CLEAN_STATE=false IMG_SIZE_MB=8192 bash build.sh --non-interactive > /tmp/gentooha_rebuild_s6_s11.log 2>&1