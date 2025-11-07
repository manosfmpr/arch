#!/usr/bin/env bash
# Minimal Arch Linux automated installer (BIOS only)
# Ultra-light build: XFCE + Firefox (Netflix/YouTube) + PipeWire
# Optimized for lowest RAM, CPU, and fastest boot

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
pacstrap /mnt base linux linux-firmware vim networkmanager sudo intel-ucode zram-generator

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

echo ">>> Installing GUI, Firefox, PipeWire, VAAPI..."
pacman -S --noconfirm xorg xfce4 lightdm lightdm-gtk-greeter firefox \
  mesa vulkan-intel libva-intel-driver intel-media-driver \
  ffmpeg gvfs gvfs-mtp xdg-user-dirs noto-fonts wget unzip \
  pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol

systemctl enable lightdm

echo ">>> Setting up autologin for LightDM..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat <<AUTOLOGIN > /etc/lightdm/lightdm.conf.d/50-autologin.conf
[Seat:*]
autologin-user=$USERNAME
autologin-user-timeout=0
session-wrapper=/etc/lightdm/Xsession
AUTOLOGIN

echo ">>> Setting keyboard layouts (US + Greek) with Alt+Shift..."
mkdir -p /etc/X11/xorg.conf.d
cat <<XKB > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,gr"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
XKB

echo ">>> Performance tuning..."
# Systemd speedup
sed -i 's/^#DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=5s/' /etc/systemd/system.conf
sed -i 's/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf
systemctl mask systemd-time-wait-sync.service || true

# Limit logs
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=32M/' /etc/systemd/journald.conf
echo "Storage=volatile" >> /etc/systemd/journald.conf

# Faster boot by masking heavy services
systemctl disable systemd-resolved.service systemd-timesyncd.service || true

# tmpfs for /tmp
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# zram (compressed swap)
cat <<ZRAM >/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

# Sysctl tweaks
cat <<SYSCTL >/etc/sysctl.d/99-performance.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=6
vm.dirty_background_ratio=2
SYSCTL

echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment

echo ">>> Configuring Firefox for VAAPI, DRM, and uBlock Origin..."
su - $USERNAME -c '
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
'

# Disable XFCE autostarts we don't need
mkdir -p /etc/xdg/autostart-disabled
mv /etc/xdg/autostart/{xfce4-power-manager.desktop,xfce4-notifyd.desktop} /etc/xdg/autostart-disabled/ || true

EOF

umount -R /mnt

echo ">>> Installation complete!"
echo "System optimized for fast boot and minimal resource use."
echo "XFCE autologin, US+Greek layout (Alt+Shift), Athens timezone."
echo "Firefox with VAAPI + uBlock Origin ready."
echo "Reboot and enjoy your ultra-light Arch system!"
