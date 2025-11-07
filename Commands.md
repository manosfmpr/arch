# Make installation media
lsblk
sudo dd if=archlinux-2025.11.01-x86_64.iso of=/dev/sdB bs=4M status=progress oflag=sync
sudo sync
sudo eject /dev/sdb
