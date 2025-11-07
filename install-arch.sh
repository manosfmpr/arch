#!/usr/bin/env bash
# Minimal Arch Linux automated installer (BIOS only)
# XFCE4 with LightDM
# Optimized for Netflix/YouTube, low RAM, VAAPI + PipeWire + Greek keyboard

# Boot into Arch linux live usb and run
# bash install-arch.sh /dev/sda my_hostname my_username

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <disk> <hostname> <username>"
    echo "Example: $0 /dev/sda archbook user"
    exit 1
fi

DISK="$1"
HOSTNAME="$2"
USERNAME="$3"

timedatectl set-ntp true

echo ">>> Partitioning $DISK for BIOS..."
parted --script "$DISK" \
  mklabel msdos \
  mkpart primary ext4 1MiB 100% \
  set 1 boot on

mkfs.ext4 "${DISK}1"
mount "${DISK}1" /mnt

echo ">>> Installing base system..."
pacstrap /mnt base linux linux-firmware vim networkmanager sudo intel-ucode

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e

echo ">>> Setting timezone, locale, and hostname..."
ln -sf /usr/share/zoneinfo/Europe/Athens /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "el_GR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

echo ">>> Configuring network..."
systemctl enable NetworkManager

echo ">>> Creating user..."
useradd -m -G wheel -s /bin/bash $USERNAME
echo "root:root" | chpasswd
echo "$USERNAME:$USERNAME" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/99_wheel

echo ">>> Installing GRUB bootloader (BIOS mode)..."
pacman -S --noconfirm grub
grub-install --target=i386-pc "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> Installing GUI, Firefox, VAAPI, and PipeWire..."
pacman -S --noconfirm xorg xfce4 lightdm lightdm-gtk-greeter firefox \
  mesa vulkan-intel libva-intel-driver intel-media-driver \
  ffmpeg htop gvfs gvfs-mtp xdg-user-dirs noto-fonts unzip wget \
  pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol

systemctl enable lightdm

echo ">>> Setting up autologin for LightDM..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<AUTOLOGIN > /etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=$USERNAME
autologin-user-timeout=0
AUTOLOGIN

echo ">>> Setting keyboard layouts (US + Greek) with Alt+Shift switch..."
mkdir -p /etc/X11/xorg.conf.d
cat <<XKB > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,gr"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
XKB

echo ">>> Optimizing system for low memory and smooth playback..."
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=50M/' /etc/systemd/journald.conf
echo "vm.swappiness=10" >> /etc/sysctl.d/99-optimizations.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-optimizations.conf

echo ">>> Setting environment for Firefox hardware acceleration..."
echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment

echo ">>> Configuring Firefox profile with VAAPI, DRM, and uBlock Origin..."
su - $USERNAME -c '
# Create Firefox profile
firefox --headless & sleep 5; killall firefox || true

PROFILE_DIR=\$(find ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default-release" | head -n 1)
if [ -z "\$PROFILE_DIR" ]; then
  mkdir -p ~/.mozilla/firefox/default-release
  PROFILE_DIR=~/.mozilla/firefox/default-release
fi

cat <<PREFS > "\$PROFILE_DIR/user.js"
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.ffvpx.enabled", false);
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("media.rdd-process.enabled", false);
user_pref("media.eme.enabled", true);
user_pref("media.gmp-widevinecdm.enabled", true);
user_pref("media.wmf.vp9.enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.firstRunURL", "");
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("extensions.pocket.enabled", false);
PREFS

UBLOCK_URL="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
wget -O /tmp/ublock.xpi "\$UBLOCK_URL"
mkdir -p "\$PROFILE_DIR/extensions"
cp /tmp/ublock.xpi "\$PROFILE_DIR/extensions/uBlock0@raymondhill.net.xpi"

echo "Firefox profile configured with uBlock Origin and hardware acceleration."
'

EOF

umount -R /mnt

echo ">>> Installation complete!"
echo ">>> Timezone: Europe/Athens"
echo ">>> Keyboard: US + Greek (Alt+Shift to switch)"
echo ">>> PipeWire enabled for audio"
echo ">>> Firefox preconfigured with VAAPI + uBlock Origin"
echo ">>> Autologin into XFCE ready. Reboot and enjoy!"
