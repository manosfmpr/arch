#!/usr/bin/env bash
# Minimal Arch Linux Installer (BIOS only, wipes disk)
# Usage: bash minimal-arch.sh /dev/sda my_hostname my_username

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <disk> <hostname> <username>"
    exit 1
fi

DISK="$1"
HOSTNAME="$2"
USERNAME="$3"

timedatectl set-ntp true

echo ">>> Wiping and partitioning $DISK..."
parted --script "$DISK" \
  mklabel msdos \
  mkpart primary ext4 1MiB 100% \
  set 1 boot on

mkfs.ext4 "${DISK}1"
mount "${DISK}1" /mnt

echo ">>> Installing base system..."
pacstrap /mnt base linux linux-firmware vim sudo networkmanager

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e

echo ">>> Locale and timezone..."
ln -sf /usr/share/zoneinfo/Europe/Athens /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

echo ">>> User creation..."
useradd -m -G wheel -s /bin/bash $USERNAME
echo "root:root" | chpasswd
echo "$USERNAME:$USERNAME" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/99_wheel

echo ">>> Network setup..."
systemctl enable NetworkManager

echo ">>> Bootloader (Syslinux)..."
pacman -S --noconfirm syslinux
syslinux-install_update -i -a -m
UUID=\$(blkid -s UUID -o value ${DISK}1)
sed -i "s|APPEND root=.*|APPEND root=UUID=\$UUID rw quiet|" /boot/syslinux/syslinux.cfg

EOF

umount -R /mnt

echo ">>> ✅ Minimal Arch installation complete!"
echo "Boot to console. NetworkManager enabled. No GUI installed."
