# Make installation media
lsblk
sudo dd if=archlinux-2025.11.01-x86_64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sudo sync
sudo eject /dev/sdb

# Erase and initialize usb
sudo umount -a
sudo wipefs --al /dev/sdb
sudo mkfs.vfat -F32 -I /dev/sdb
