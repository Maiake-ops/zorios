#!/bin/bash
# Zori OS ISO builder (headless, VMware ready)
# Requires archiso installed

set -e

cd ~
RELENG_DIR=~/zori/releng
OUTPUT_DIR=~/zori/out

mkdir zori
cp -r /usr/share/archiso/configs/releng ~/zori
cd ~/zori/releng
mkdir -p airootfs/etc/skel
cd ~
echo "preparing for building calamares"
cd ~/zori
git clone https://github.com/calamares/calamares.git calamares-src
cd calamares-src
mkdir build
mkdir -p calamares-src/build
cd calamares-src/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install DESTDIR=~/zori/releng/airootfs

echo "[*] Preparing releng tree..."
cd "$RELENG_DIR"

# -----------------------
# Step 1: Setup Plasma boot
# -----------------------
AIROOT="$RELENG_DIR/airootfs/etc"

echo "[*] Setting default graphical target..."
mkdir -p "$AIROOT/systemd/system/default.target.wants"
ln -sf /usr/lib/systemd/system/graphical.target "$AIROOT/systemd/system/default.target"

echo "[*] Enabling SDDM display manager..."
mkdir -p "$AIROOT/systemd/system"
ln -sf /usr/lib/systemd/system/sddm.service "$AIROOT/systemd/system/display-manager.service"

# -----------------------
# Step 2: Setup Calamares config
# -----------------------
echo "[*] Configuring Calamares..."
mkdir -p "$AIROOT/calamares"

# Example minimal settings
cat > "$AIROOT/calamares/settings.conf" <<EOF
---
modules-search: /usr/share/calamares/modules
sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - summary
      - install
      - finished
branding: zori
EOF

mkdir -p "$AIROOT/calamares/branding/zori"
cat > "$AIROOT/calamares/branding/zori/branding.desc" <<EOF
---
name: "Zori OS"
version: "1.0"
welcomeStyle: "banner"
windowPlacement: "center"
windowSize: 1024x768
productName: "Zori OS"
shortProductName: "Zori"
EOF

# -----------------------
# Step 3: Build ISO
# -----------------------
echo "[*] Building ISO..."
mkdir -p "$OUTPUT_DIR"
sudo mkarchiso -v -o "$OUTPUT_DIR"

echo "[*] Done! Zori OS ISO is ready."
