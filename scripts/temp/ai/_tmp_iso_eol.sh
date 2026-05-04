ISO=/mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-debug.iso
M=$(mktemp -d)
mount -o loop "$ISO" "$M"
echo "--- grub.cfg with EOL markers ---"
sed -n '1,120l' "$M/boot/grub/grub.cfg"
umount "$M"
rmdir "$M"