#!/usr/bin/env bash
set -euo pipefail
cd /mnt/c/Users/tamus/projects/linux/home_assistant_1
source scripts/gentoo/common.sh
mount_chroot_fs
KFILE=$(ls -1 /mnt/gentoo/boot/kernel-* | sort -V | tail -n1)
KVER=${KFILE##*/kernel-}
echo "KVER=$KVER"
cat >/mnt/gentoo/tmp/in_chroot_dracut.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
dracut --force --kver "$KVER" --add dmsquash-live -v "/boot/initramfs-$KVER.img"
EOF
chmod +x /mnt/gentoo/tmp/in_chroot_dracut.sh
chroot /mnt/gentoo /bin/bash /tmp/in_chroot_dracut.sh
