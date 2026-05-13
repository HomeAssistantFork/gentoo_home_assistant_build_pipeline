set -euo pipefail
for f in /mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-live.iso /mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-debug.iso /mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-installer.iso; do
  echo "==== $f ===="
  blkid -o full "$f" | sed -n '1p'
  mnt=$(mktemp -d)
  mount -o loop "$f" "$mnt"
  sed -n '1,80p' "$mnt/boot/grub/grub.cfg"
  umount "$mnt"
  rmdir "$mnt"
  echo
 done