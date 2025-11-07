#!/usr/bin/env bash
# Ultra-minimal Arch Linux (BIOS only)
# i3 + Firefox (Netflix/YouTube) + Picom + Syslinux + PipeWire
# Boots directly to i3 — optimized for low RAM and fast performance

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

echo ">>> Partitioning $DISK..."
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

echo ">>> Locale and timezone..."
ln -sf /usr/share/zoneinfo/Europe/Athens /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "el_GR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

echo ">>> Network setup..."
systemctl enable NetworkManager

echo ">>> User creation..."
useradd -m -G wheel -s /bin/bash $USERNAME
echo "root:root" | chpasswd
echo "$USERNAME:$USERNAME" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/99_wheel

echo ">>> Bootloader: Syslinux..."
pacman -S --noconfirm syslinux
syslinux-install_update -i -a -m
UUID=\$(blkid -s UUID -o value ${DISK}1)
sed -i "s|APPEND root=.*|APPEND root=UUID=\$UUID rw quiet|" /boot/syslinux/syslinux.cfg

echo ">>> Installing GUI packages..."
pacman -S --noconfirm xorg xorg-xinit i3-wm i3status dmenu \
  picom network-manager-applet nm-connection-editor \
  firefox mesa vulkan-intel libva-intel-driver intel-media-driver \
  ffmpeg pipewire pipewire-alsa pipewire-pulse wireplumber \
  xterm noto-fonts wget unzip

echo ">>> Keyboard (US + Greek, Alt+Shift)..."
mkdir -p /etc/X11/xorg.conf.d
cat <<XKB > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us,gr"
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
XKB

echo ">>> Performance optimizations..."
# Journald smaller logs, tmpfs for /tmp, zram
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=32M/' /etc/systemd/journald.conf
echo "Storage=volatile" >> /etc/systemd/journald.conf
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

cat <<ZRAM >/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRAM

cat <<SYSCTL >/etc/sysctl.d/99-performance.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=6
vm.dirty_background_ratio=2
SYSCTL

echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment

echo ">>> Autologin to i3..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat <<AUTOLOGIN > /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I 38400 linux
AUTOLOGIN
systemctl enable getty@tty1.service

su - $USERNAME -c '
echo "exec i3" > ~/.xinitrc
echo "if [[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then exec startx; fi" >> ~/.bash_profile

mkdir -p ~/.config/i3
cat <<I3CONF > ~/.config/i3/config
set \$mod Mod1
font pango:Noto Sans 10

exec --no-startup-id nm-applet
exec --no-startup-id pipewire
exec --no-startup-id wireplumber
exec --no-startup-id picom --experimental-backends --no-fading-openclose --backend glx --vsync
exec --no-startup-id firefox

bindsym \$mod+Return exec xterm
bindsym \$mod+d exec dmenu_run
bindsym \$mod+Shift+q kill
bindsym \$mod+Shift+e exec "i3-msg exit"

bar {
    status_command i3status
}
I3CONF
'

echo ">>> Preconfiguring Firefox (VAAPI, DRM, uBlock Origin)..."
su - $USERNAME -c '
firefox --headless & sleep 5; killall firefox || true
PROFILE_DIR=\$(find ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default-release" | head -n 1)
[ -z "\$PROFILE_DIR" ] && mkdir -p ~/.mozilla/firefox/default-release && PROFILE_DIR=~/.mozilla/firefox/default-release

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

echo ">>> Disabling unnecessary services..."
systemctl disable systemd-resolved.service systemd-timesyncd.service || true
systemctl mask systemd-time-wait-sync.service || true

EOF

umount -R /mnt

echo ">>> ✅ Installation complete!"
echo "System will boot directly into i3."
echo "Firefox, Picom, PipeWire, and Wi-Fi applet start automatically."
echo "Keyboard: US + Greek (Alt+Shift). Timezone: Athens."
echo "Expected idle RAM ≈ 230 MB, boot ≈ 5 s."
