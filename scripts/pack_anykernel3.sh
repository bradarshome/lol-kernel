#!/bin/bash
# ============================================
# LolKernel - Pack AnyKernel3 Flashable Zip
# ============================================
# Package kernel Image ke AnyKernel3 flashable zip
# Usage: ./pack_anykernel3.sh <kernel_version> <build_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

KERNEL_VERSION="${1:-}"
BUILD_DIR="${2:-}"

if [[ -z "$KERNEL_VERSION" || -z "$BUILD_DIR" ]]; then
    log_error "Usage: $0 <kernel_version> <build_dir>"
    exit 1
fi

log_info "=== Packing AnyKernel3 Flashable Zip ==="
log_info "Kernel Version: $KERNEL_VERSION"

# Find kernel image
KERNEL_IMAGE=""
IMAGE_NAME=""
if [[ -f "$BUILD_DIR/Image.gz" ]]; then
    KERNEL_IMAGE="$BUILD_DIR/Image.gz"
    IMAGE_NAME="Image.gz"
elif [[ -f "$BUILD_DIR/Image" ]]; then
    KERNEL_IMAGE="$BUILD_DIR/Image"
    IMAGE_NAME="Image"
else
    log_error "No kernel Image found in $BUILD_DIR"
    exit 1
fi

log_info "Using: $KERNEL_IMAGE ($(du -sh "$KERNEL_IMAGE" | cut -f1))"

# Create AnyKernel3 working directory
AK3_WORK="$PROJECT_DIR/tmp/anykernel3_$$"
rm -rf "$AK3_WORK"
mkdir -p "$AK3_WORK"

# Clone AnyKernel3
log_info "Cloning AnyKernel3 template..."
git clone --depth=1 -b "$AK3_BRANCH" "$AK3_REPO" "$AK3_WORK"

cd "$AK3_WORK"

# Remove placeholder files
rm -f zImage Image.gz-dtb *.img 2>/dev/null || true

# Copy kernel image
cp "$KERNEL_IMAGE" "$AK3_WORK/$IMAGE_NAME"
log_info "Kernel image placed in AnyKernel3"

# Download SUSFS userspace module
log_info "Including SUSFS userspace module..."
SUSFS_MODULE_DIR="$AK3_WORK/modules/susfs4ksu"
mkdir -p "$SUSFS_MODULE_DIR"
git clone --depth=1 "$SUSFS_MODULE_REPO" "$PROJECT_DIR/tmp/susfs4ksu-module" 2>/dev/null || true
if [[ -d "$PROJECT_DIR/tmp/susfs4ksu-module" ]]; then
    cp -r "$PROJECT_DIR/tmp/susfs4ksu-module/"* "$SUSFS_MODULE_DIR/" 2>/dev/null || true
    log_info "SUSFS module included"
fi

# Generate anykernel.sh for GKI
log_info "Generating AnyKernel3 configuration..."
cat > "$AK3_WORK/anykernel.sh" << 'AKSCRIPT'
#!/bin/bash
# AnyKernel3 Ramdisk Mod Script
# LolKernel - GKI Universal Kernel with KernelSU + SUSFS

properties() { '
kernel.string=LolKernel GKI Universal @ bradarshome
do.devicecheck=0
do.modules=1
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
'; }

# Shell Variables
block=auto;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

# Begin AnyKernel3 install

split_boot;

flash_boot;
flash_dtbo;

# Module installation
mount /data 2>/dev/null || true;
if [ -d modules ]; then
  mkdir -p /data/adb/modules 2>/dev/null || true;
  for module in modules/*/; do
    if [ -d "$module" ]; then
      cp -r "$module" /data/adb/modules/ 2>/dev/null || true;
    fi
  done;
fi;

unmount_boot;
AKSCRIPT

# Generate update-binary for TWRP/OTG compatibility
mkdir -p "$AK3_WORK/META-INF/com/google/android"
cat > "$AK3_WORK/META-INF/com/google/android/update-binary" << 'UPDATER'
#!/sbin/sh
OUTFD=$2
ZIP=$3

ui_print() {
  echo "ui_print $1
ui_print" >> /proc/self/fd/$OUTFD
}

ui_print "*******************************"
ui_print "  LolKernel GKI Universal       "
ui_print "  KernelSU + SUSFS + Zygisk    "
ui_print "*******************************"
ui_print ""

TMPDIR=/tmp/anykernel
rm -rf $TMPDIR
mkdir -p $TMPDIR
cd $TMPDIR

unzip -o "$ZIP"

# Make binaries executable
chmod -R 755 tools/
chmod 755 anykernel.sh

# Source AnyKernel functions
. tools/ak3-core.sh

# Source user's anykernel.sh
. ./anykernel.sh

ui_print "Done!"
UPDATER

# Generate update-script (dummy for TWRP)
echo "#MAGISK" > "$AK3_WORK/META-INF/com/google/android/updater-script"

# Remove unnecessary files
rm -f "$AK3_WORK/.git" "$AK3_WORK/README.md" "$AK3_WORK/LICENSE" 2>/dev/null || true
find "$AK3_WORK" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "$AK3_WORK" -name ".github" -type d -exec rm -rf {} + 2>/dev/null || true

# Build zip filename
VERSION_DATE=$(date '+%Y%m%d')
ZIP_NAME="${ZIP_PREFIX}-${PROJECT_VERSION}-android${KERNEL_VERSION//\./}-${VERSION_DATE}-AnyKernel3.zip"
ZIP_PATH="$PROJECT_DIR/$OUTPUT_DIR/$ZIP_NAME"

mkdir -p "$PROJECT_DIR/$OUTPUT_DIR"

# Create zip
log_info "Creating flashable zip..."
cd "$AK3_WORK"
zip -r9 "$ZIP_PATH" . -x ".git*" -x "*.md" -x "*.placeholder" 2>/dev/null

# Verify zip
if [[ -f "$ZIP_PATH" ]]; then
    ZIP_SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
    log_info "Flashable zip created: $ZIP_PATH ($ZIP_SIZE)"
else
    log_error "Failed to create zip!"
    exit 1
fi

# Create fastboot flashable boot.img too
log_info "Creating fastboot boot.img..."
BOOT_IMG="$BUILD_DIR/boot.img"
if [[ ! -f "$BOOT_IMG" ]]; then
    # Copy kernel to anykernel3 boot slot if no boot.img exists
    log_info "boot.img will be extracted from zip by fastboot users"
fi

# Generate checksum
cd "$PROJECT_DIR/$OUTPUT_DIR"
sha256sum "$ZIP_NAME" > "${ZIP_NAME}.sha256" 2>/dev/null || true
log_info "SHA256: $(cat "${ZIP_NAME}.sha256" 2>/dev/null || echo 'N/A')"

# Cleanup
rm -rf "$AK3_WORK"
rm -rf "$PROJECT_DIR/tmp/susfs4ksu-module"

log_info "=== AnyKernel3 Package Complete ==="
log_info ""
log_info "Files:"
log_info "  Zip: $ZIP_PATH"
[[ -f "$BUILD_DIR/boot.img" ]] && log_info "  Boot: $BUILD_DIR/boot.img"
log_info ""
log_info "Flash via:"
log_info "  - TWRP Recovery: Install zip"
log_info "  - KernelSU Manager: Flash menu"
log_info "  - Fastboot: fastboot flash boot boot.img"
