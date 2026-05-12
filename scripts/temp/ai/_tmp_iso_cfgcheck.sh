set -euo pipefail
for f in /mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-debug.iso /mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-installer.iso; do
  echo "==== $f ===="
  M=$(mktemp -d)
  mount -o loop "$f" "$M"
  sed -n '1,80p' "$M/boot/grub/grub.cfg"
  umount "$M"
  rmdir "$M"
  echo
 done