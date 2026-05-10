set -euo pipefail
for f in /var/lib/ha-gentoo-hybrid/artifacts/gentooha-x64-live.iso /var/lib/ha-gentoo-hybrid/artifacts/gentooha-x64-debug.iso /var/lib/ha-gentoo-hybrid/artifacts/gentooha-x64-installer.iso; do
  echo "==== $f ===="
  blkid -o full "$f" || true
  xorriso -indev "$f" -pvd_info | grep -E "Volume id|System id" || true
  echo
 done