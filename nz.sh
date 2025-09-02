#!/bin/bash
# Zori OS ISO Builder (headless, VMware ready)
# Enhanced version with better error handling and organization
# Requires: archiso, git, cmake, make, base-devel

set -euo pipefail  # Enhanced error handling

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORK_DIR="${HOME}/zori"
readonly RELENG_DIR="${WORK_DIR}/releng"
readonly OUTPUT_DIR="${WORK_DIR}/out"
readonly CALAMARES_VERSION="v3.3.9"
readonly LOG_FILE="${WORK_DIR}/build.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Build failed with exit code $exit_code. Check $LOG_FILE for details."
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_deps=()
    
    for cmd in archiso-releng git cmake make; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing_deps[*]}. Please install them first."
    fi
    
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended. Consider running as a regular user."
    fi
    
    log "Prerequisites check passed"
}

# Setup working directory
setup_workspace() {
    log "Setting up workspace at $WORK_DIR..."
    
    # Remove existing directory if it exists
    if [[ -d "$WORK_DIR" ]]; then
        warn "Existing workspace found. Removing..."
        rm -rf "$WORK_DIR"
    fi
    
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
    cd "$WORK_DIR"
    
    # Initialize log file
    touch "$LOG_FILE"
    log "Workspace created successfully"
}

# Copy and prepare releng configuration
prepare_releng() {
    log "Preparing releng configuration..."
    
    if [[ ! -d "/usr/share/archiso/configs/releng" ]]; then
        error "archiso releng config not found. Is archiso properly installed?"
    fi
    
    cp -r /usr/share/archiso/configs/releng "$RELENG_DIR"
    mkdir -p "$RELENG_DIR/airootfs/etc/skel"
    
    log "Releng configuration prepared"
}

# Build Calamares installer
build_calamares() {
    log "Building Calamares installer..."
    
    cd "$WORK_DIR"
    
    # Clone Calamares if not already present
    if [[ ! -d "calamares-src" ]]; then
        info "Cloning Calamares $CALAMARES_VERSION..."
        git clone --branch "$CALAMARES_VERSION" --depth 1 \
            https://github.com/calamares/calamares.git calamares-src
    else
        info "Calamares source already exists, skipping clone"
    fi
    
    cd calamares-src
    
    # Clean previous build
    if [[ -d "build" ]]; then
        warn "Removing previous build directory"
        rm -rf build
    fi
    
    mkdir build
    cd build
    
    info "Configuring Calamares build..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DWITH_PYTHONQT=OFF \
        >> "$LOG_FILE" 2>&1
    
    info "Building Calamares (this may take a while)..."
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1
    
    info "Installing Calamares to airootfs..."
    make install DESTDIR="$RELENG_DIR/airootfs" >> "$LOG_FILE" 2>&1
    
    log "Calamares build completed successfully"
}

# Configure system services
configure_services() {
    log "Configuring system services..."
    
    local airoot="$RELENG_DIR/airootfs/etc"
    
    # Set graphical target as default
    info "Setting default graphical target..."
    mkdir -p "$airoot/systemd/system"
    ln -sf /usr/lib/systemd/system/graphical.target "$airoot/systemd/system/default.target"
    
    # Enable SDDM display manager
    info "Enabling SDDM display manager..."
    ln -sf /usr/lib/systemd/system/sddm.service "$airoot/systemd/system/display-manager.service"
    
    # Enable NetworkManager
    info "Enabling NetworkManager..."
    mkdir -p "$airoot/systemd/system/multi-user.target.wants"
    ln -sf /usr/lib/systemd/system/NetworkManager.service "$airoot/systemd/system/multi-user.target.wants/"
    
    log "System services configured"
}

# Configure Calamares installer
configure_calamares() {
    log "Configuring Calamares installer..."
    
    local calamares_dir="$RELENG_DIR/airootfs/etc/calamares"
    local branding_dir="$calamares_dir/branding/zori"
    
    mkdir -p "$calamares_dir" "$branding_dir"
    
    # Main Calamares configuration
    info "Creating Calamares settings..."
    cat > "$calamares_dir/settings.conf" <<'EOF'
---
modules-search: [ local, /usr/share/calamares/modules ]

instances:
- id:       rootfs
  module:   unpackfs
  config:   unpackfs_rootfs.conf

- id:       vmlinuz
  module:   unpackfs
  config:   unpackfs_vmlinuz.conf

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs@rootfs
  - unpackfs@vmlinuz
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - luksbootkeyfile
  - luksopenswaphookcfg
  - initcpiocfg
  - initcpio
  - removeuser
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
  - bootloader
  - grubcfg
  - umount
- show:
  - finished

branding: zori

prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: false
hide-back-and-next-during-exec: false
quit-at-end: false
EOF

    # Branding configuration
    info "Creating branding configuration..."
    cat > "$branding_dir/branding.desc" <<'EOF'
---
componentName: zori

welcomeStyleCalamares: "both"
welcomeExpandingLogo: true

strings:
    productName: "Zori OS"
    shortProductName: "Zori"
    version: "1.0"
    shortVersion: "1.0"
    versionedName: "Zori OS 1.0"
    shortVersionedName: "Zori 1.0"
    bootloaderEntryName: "Zori"
    productUrl: "https://zori-os.org"
    supportUrl: "https://zori-os.org/support"
    knownIssuesUrl: "https://zori-os.org/issues"
    releaseNotesUrl: "https://zori-os.org/releases"
    donateUrl: "https://zori-os.org/donate"

images:
    productLogo: "logo.png"
    productIcon: "logo.png"
    productWelcome: "welcome.png"

style:
   sidebarBackground: "#2c3e50"
   sidebarText: "#ffffff"
   sidebarTextSelect: "#4FC3F7"
   sidebarTextCurrent: "#4FC3F7"

slideshows:
- "show.qml"

uploadServer:
    type:    "fiche"
    url:     "http://termbin.com:9999"
    sizeLimit: -1
EOF

    log "Calamares configuration completed"
}

# Add essential packages to the ISO
configure_packages() {
    log "Configuring packages for ISO..."
    
    local packages_file="$RELENG_DIR/packages.x86_64"
    
    # Add essential packages for Zori OS
    info "Adding additional packages..."
    cat >> "$packages_file" <<'EOF'

# Desktop Environment
plasma-meta
sddm
sddm-kcm

# System & Network
networkmanager
network-manager-applet
bluez
bluez-utils
cups
print-manager

# Applications - Internet
firefox
thunderbird
ktorrent

# Applications - Multimedia
vlc
gwenview
kamoso
elisa
k3b

# Applications - Office & Productivity
libreoffice-fresh
okular
ark
kcalc
kcharselect

# Applications - System
kate
kwrite
dolphin
konsole
spectacle
ksystemlog
htop
neofetch
partitionmanager

# Development Tools
git
vim
nano
base-devel

# System Utilities
calamares
gparted
timeshift
bleachbit

# Fonts
ttf-liberation
ttf-dejavu
noto-fonts
noto-fonts-emoji

# Codecs & Drivers
mesa
xf86-video-vmware
open-vm-tools
EOF

    log "Package configuration completed"
}

# Create ISO image
build_iso() {
    log "Building Zori OS ISO..."
    
    cd "$RELENG_DIR"
    
    # Ensure output directory exists and is writable
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        error "Output directory $OUTPUT_DIR is not writable"
    fi
    
    info "Starting ISO build process (this may take 30+ minutes)..."
    if sudo mkarchiso -v -w /tmp/archiso-tmp -o "$OUTPUT_DIR" .; then
        log "ISO build completed successfully!"
        
        # Find and display the created ISO
        local iso_file
        iso_file=$(find "$OUTPUT_DIR" -name "*.iso" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -n "$iso_file" && -f "$iso_file" ]]; then
            local iso_size
            iso_size=$(du -h "$iso_file" | cut -f1)
            log "Created ISO: $iso_file ($iso_size)"
            log "MD5: $(md5sum "$iso_file" | cut -d' ' -f1)"
        else
            warn "ISO file not found in output directory"
        fi
    else
        error "ISO build failed. Check the log for details."
    fi
}

# Main execution function
main() {
    log "Starting Zori OS ISO build process..."
    
    check_prerequisites
    setup_workspace
    prepare_releng
    build_calamares
    build_yay
    configure_services
    configure_calamares
    configure_packages
    build_iso
    
    log "Zori OS ISO build process completed successfully!"
    log "Build log saved to: $LOG_FILE"
}

# Quick diagnosis function
diagnose() {
    echo "=== Zori OS Build Diagnostics ==="
    echo "System: $(uname -a)"
    echo "Distribution: $(cat /etc/os-release | grep PRETTY_NAME || echo 'Unknown')"
    echo "User: $(whoami) (UID: $EUID)"
    echo "Working directory: $PWD"
    echo "Free space: $(df -h . | tail -1 | awk '{print $4}')"
    echo ""
    echo "Dependencies check:"
    for cmd in git cmake make go mkarchiso; do
        if command -v "$cmd" &> /dev/null; then
            echo "✓ $cmd: $(command -v "$cmd")"
        else
            echo "✗ $cmd: NOT FOUND"
        fi
    done
    echo ""
    echo "Key paths:"
    [[ -d "/usr/share/archiso/configs/releng" ]] && echo "✓ archiso releng config found" || echo "✗ archiso releng config missing"
    [[ -f "$LOG_FILE" ]] && echo "✓ Log file: $LOG_FILE" || echo "✗ No log file yet"
    echo ""
    if [[ -f "$LOG_FILE" ]]; then
        echo "Last 10 log entries:"
        tail -10 "$LOG_FILE"
    fi
}

# Script entry point with argument handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-build}" in
        "diagnose"|"diag"|"debug")
            diagnose
            ;;
        "build"|"")
            main "$@"
            ;;
        "help"|"-h"|"--help")
            echo "Zori OS ISO Builder"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  build     - Build the ISO (default)"
            echo "  install   - Install dependencies only"
            echo "  diagnose  - Run diagnostics"
            echo "  help      - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build ISO with auto-dependency installation"
            echo "  $0 install           # Install dependencies only"
            echo "  $0 diagnose          # Check system and troubleshoot"
            ;;
        *)
            error "Unknown command: $1. Use '$0 help' for usage."
            ;;
    esac
fi
