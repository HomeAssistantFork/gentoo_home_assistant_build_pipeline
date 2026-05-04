set -euo pipefail
ISO=/mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-debug.iso
M=$(mktemp -d)
mount -o loop "$ISO" "$M"
echo "ISO_LABEL:"
blkid -o value -s LABEL "$ISO"
echo "--- grub.cfg ---"
sed -n '1,240p' "$M/boot/grub/grub.cfg"
echo "--- boot tree ---"
find "$M/boot" -maxdepth 2 -type f | sed "s#^$M##" | sort
umount "$M"
rmdir "$M"