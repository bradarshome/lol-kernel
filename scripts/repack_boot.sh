#!/bin/bash
# ============================================
# LolKernel - Repack Boot Image
# ============================================
# Repack kernel Image ke boot.img menggunakan magiskboot
# Usage: ./repack_boot.sh <kernel_version> <build_dir> [stock_boot.img]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

KERNEL_VERSION="${1:-}"
BUILD_DIR="${2:-}"
STOCK_BOOT="${3:-}"

if [[ -z "$KERNEL_VERSION" || -z "$BUILD_DIR" ]]; then
    log_error "Usage: $0 <kernel_version> <build_dir> [stock_boot.img]"
    log_error ""
    log_error "If stock_boot.img is provided, kernel will be repacked into it."
    log_error "Otherwise, AnyKernel3 zip will be used for flashing."
    exit 1
fi

log_info "=== Repack Boot Image ==="
log_info "Kernel Version: $KERNEL_VERSION"
log_info "Build Dir: $BUILD_DIR"

# Find kernel image
KERNEL_IMAGE=""
if [[ -f "$BUILD_DIR/Image.gz" ]]; then
    KERNEL_IMAGE="$BUILD_DIR/Image.gz"
elif [[ -f "$BUILD_DIR/Image" ]]; then
    KERNEL_IMAGE="$BUILD_DIR/Image"
else
    log_error "No kernel Image found in $BUILD_DIR"
    exit 1
fi

log_info "Using kernel image: $KERNEL_IMAGE"

# If no stock boot.img, skip repack - AnyKernel3 will handle it
if [[ -z "$STOCK_BOOT" ]]; then
    log_info "No stock boot.img provided - skipping repack."
    log_info "Use AnyKernel3 zip for flashing (pack_anykernel3.sh)."
    exit 0
fi

if [[ ! -f "$STOCK_BOOT" ]]; then
    log_error "Stock boot.img not found: $STOCK_BOOT"
    exit 1
fi

# Check for magiskboot
if ! command -v magiskboot &>/dev/null; then
    log_warn "magiskboot not found, attempting to download..."
    MAGISKBOOT_URL="https://raw.githubusercontent.com/topjohnwu/Magisk/master/native/jni/external/magiskboot/magiskboot64"
    wget -q -O /tmp/magiskboot "$MAGISKBOOT_URL" || true
    chmod +x /tmp/magiskboot 2>/dev/null || true
    MAGISKBOOT="/tmp/magiskboot"
else
    MAGISKBOOT="magiskboot"
fi

if ! command -v "$MAGISKBOOT" &>/dev/null; then
    log_error "magiskboot not available. Use AnyKernel3 instead."
    exit 1
fi

# Work in temp directory
REPACK_DIR="$PROJECT_DIR/tmp/repack_$$"
mkdir -p "$REPACK_DIR"
cp "$STOCK_BOOT" "$REPACK_DIR/boot.img"

cd "$REPACK_DIR"

log_info "Unpacking stock boot.img..."
"$MAGISKBOOT" unpack boot.img

# Replace kernel
if [[ -f "$KERNEL_IMAGE" ]]; then
    if [[ "$KERNEL_IMAGE" == *.gz ]]; then
        cp "$KERNEL_IMAGE" kernel
    else
        # Compress if needed
        gzip -9 -c "$KERNEL_IMAGE" > kernel
    fi
    log_info "Kernel replaced"
else
    log_error "Kernel image not found!"
    exit 1
fi

log_info "Repacking boot.img..."
"$MAGISKBOOT" repack boot.img new-boot.img

# Copy output
OUTPUT_FILE="$BUILD_DIR/boot.img"
cp new-boot.img "$OUTPUT_FILE"
log_info "Repacked boot.img: $OUTPUT_FILE ($(du -sh "$OUTPUT_FILE" | cut -f1))"

# Cleanup
rm -rf "$REPACK_DIR"

log_info "=== Repack Complete ==="
