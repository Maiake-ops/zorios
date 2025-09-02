#!/bin/bash
# Zori OS Arch-based distro builder
# Supports Hyprland or KDE Plasma (Wayland)
# Includes fastfetch, yay, Calamares (AUR)

set -e

DISTRO_DIR=~/zori
DISTRO_NAME="zori-os"
ISO_OUT=~/iso-out

echo ">>> Building $DISTRO_NAME ..."

# Ask which desktop to build
read -p "Choose desktop (hyprland/plasma): " DESKTOP

# 1. Install archiso + deps
sudo pacman -S --needed --noconfirm archiso git base-devel go cmake extra-cmake-modules qt5-base qt5-tools boost yaml-cpp meson ninja wlroots wayland fastfetch

# 2. Copy releng profile
if [ ! -d "$DISTRO_DIR" ]; then
    cp -r /usr/share/archiso/configs/releng $DISTRO_DIR
fi

cd $DISTRO_DIR/releng

# 3. Base packages
cat >> packages.x86_64 <<EOF

# --- Common ---
firefox
nano
git
go
base-devel
cmake
extra-cmake-modules
qt5-base
qt5-tools
boost
yaml-cpp
fastfetch
EOF

# 4. Desktop choice
if [[ "$DESKTOP" == "plasma" ]]; then
    echo ">>> Adding KDE Plasma packages..."
    cat >> packages.x86_64 <<EOF

# --- KDE Plasma Wayland ---
plasma-meta
kde-applications
konsole
dolphin
kate
EOF

    # Plasma autostart for Calamares
    mkdir -p airootfs/etc/skel/.config/autostart
    cat > airootfs/etc/skel/.config/autostart/calamares.desktop <<'EOF'
[Desktop Entry]
Type=Application
Exec=sudo calamares
Name=Calamares Installer
X-GNOME-Autostart-enabled=true
EOF

elif [[ "$DESKTOP" == "hyprland" ]]; then
    echo ">>> Adding Hyprland packages..."
    cat >> packages.x86_64 <<EOF

# --- Hyprland ---
hyprland
xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk
waybar
wofi
alacritty
thunar
EOF

    # Hyprland config
    mkdir -p airootfs/etc/skel/.config/hypr
    cat > airootfs/etc/skel/.config/hypr/hyprland.conf <<'EOF'
monitor=,preferred,auto,auto
exec-once = waybar
exec-once = wofi --show drun
exec-once = alacritty
exec-once = fastfetch
EOF

    # Autostart Calamares in Hyprland
    mkdir -p airootfs/etc/skel/.config/autostart
    cat > airootfs/etc/skel/.config/autostart/calamares.desktop <<'EOF'
[Desktop Entry]
Type=Application
Exec=sudo calamares
Name=Calamares Installer
X-GNOME-Autostart-enabled=true
EOF
else
    echo "❌ Unknown desktop option. Use 'hyprland' or 'plasma'."
    exit 1
fi

# 5. Preinstall yay into live system
mkdir -p airootfs/root
cat > airootfs/root/bootstrap-yay.sh <<'EOS'
#!/bin/bash
cd /root
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd ..
rm -rf yay-bin
EOS
chmod +x airootfs/root/bootstrap-yay.sh

# 6. Build Calamares from AUR inside live system
cat > airootfs/root/bootstrap-calamares.sh <<'EOS'
#!/bin/bash
# Requires yay first
/root/bootstrap-yay.sh
yay -S --noconfirm calamares calamares-config-arch
EOS
chmod +x airootfs/root/bootstrap-calamares.sh

# 7. Write profiledef.sh
cat > profiledef.sh <<EOF
#!/usr/bin/env bash
# Profile definition for Zori OS

iso_name="$DISTRO_NAME"
iso_label="ZORI_$(date +%Y%m)"
iso_publisher="Zori OS Project <https://example.com>"
iso_application="Zori OS Live ISO"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers"]="0:0:440"
  ["/etc/sudoers.d"]="0:0:750"
)
EOF

# 8. Build ISO
mkdir -p $ISO_OUT
mkarchiso -v -o $ISO_OUT .

echo "✅ Build complete! ISO is in $ISO_OUT"
echo "⚡ Inside live ISO, run: sudo /root/bootstrap-calamares.sh"
