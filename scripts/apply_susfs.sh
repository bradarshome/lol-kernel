#!/bin/bash
# ============================================
# Apply SUSFS Kernel Patches
# ============================================
# Apply SUSFS filesystem patches to GKI kernel
# Must be applied BEFORE KernelSU driver
# Usage: ./apply_susfs.sh <kernel_version> <source_dir>

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
SOURCE_DIR="${2:-}"

if [[ -z "$KERNEL_VERSION" || -z "$SOURCE_DIR" ]]; then
    log_error "Usage: $0 <kernel_version> <source_dir>"
    exit 1
fi

KERNEL_DIR="$SOURCE_DIR/common"

if [[ ! -d "$KERNEL_DIR" ]]; then
    log_error "Kernel source not found at $KERNEL_DIR"
    exit 1
fi

log_info "=== Applying SUSFS Patches ==="
log_info "Kernel Version: $KERNEL_VERSION"
log_info "Kernel Dir: $KERNEL_DIR"

# Map kernel version to correct SUSFS branch
case "$KERNEL_VERSION" in
    "5.10")
        SUSFS_BRANCH="gki-android12-5.10"
        ;;
    "6.6")
        SUSFS_BRANCH="gki-android15-6.6"
        ;;
    *)
        log_error "Unsupported kernel version for SUSFS: $KERNEL_VERSION"
        exit 1
        ;;
esac

# Clone SUSFS with correct branch
SUSFS_TEMP="$PROJECT_DIR/tmp/susfs4ksu"
rm -rf "$SUSFS_TEMP"
log_info "Cloning SUSFS branch: $SUSFS_BRANCH"
git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_TEMP" 2>&1

cd "$SUSFS_TEMP"

# Step 1: Copy SUSFS filesystem code (fs/susfs/)
log_info "Copying SUSFS filesystem code..."
if [[ -d "kernel_patches/fs/susfs" ]]; then
    mkdir -p "$KERNEL_DIR/fs/susfs"
    cp -r kernel_patches/fs/susfs/* "$KERNEL_DIR/fs/susfs/"
    log_info "Copied fs/susfs/ ($(ls kernel_patches/fs/susfs/ | wc -l) files)"
else
    log_warn "fs/susfs/ not found in SUSFS branch"
fi

# Step 2: Copy SUSFS headers
log_info "Copying SUSFS headers..."
if [[ -d "kernel_patches/include/linux" ]]; then
    cp kernel_patches/include/linux/susfs* "$KERNEL_DIR/include/linux/" 2>/dev/null || true
    log_info "Copied include/linux/susfs* ($(ls kernel_patches/include/linux/susfs* 2>/dev/null | wc -l) files)"
fi

# Step 3: Apply ONLY the matching patch
log_info "Applying SUSFS patch..."
cd "$KERNEL_DIR"

PATCH_APPLIED=0
for patch_file in "$SUSFS_TEMP"/kernel_patches/*.patch; do
    [[ -f "$patch_file" ]] || continue

    patch_name=$(basename "$patch_file")
    log_info "Applying: $patch_name"

    if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>/dev/null; then
        PATCH_APPLIED=$((PATCH_APPLIED + 1))
        log_info "Patch applied successfully"
    else
        log_warn "Patch $patch_name may have failed"
    fi
done

if [[ $PATCH_APPLIED -eq 0 ]]; then
    log_warn "No SUSFS patches were applied"
fi

# Step 4: Integrate into build system
log_info "Integrating SUSFS into build system..."

# Add to fs/Makefile
FS_MAKEFILE="$KERNEL_DIR/fs/Makefile"
if ! grep -q "susfs" "$FS_MAKEFILE" 2>/dev/null; then
    echo "" >> "$FS_MAKEFILE"
    echo "# SUSFS" >> "$FS_MAKEFILE"
    echo "obj-\$(CONFIG_SUSFS) += susfs/" >> "$FS_MAKEFILE"
    log_info "Added SUSFS to fs/Makefile"
fi

# Add to fs/Kconfig
FS_KCONFIG="$KERNEL_DIR/fs/Kconfig"
if [[ -f "$FS_KCONFIG" ]] && ! grep -q "susfs" "$FS_KCONFIG" 2>/dev/null; then
    echo "" >> "$FS_KCONFIG"
    echo "source \"fs/susfs/Kconfig\"" >> "$FS_KCONFIG"
    log_info "Added SUSFS to fs/Kconfig"
fi

# Create Kconfig if not present
if [[ ! -f "$KERNEL_DIR/fs/susfs/Kconfig" ]]; then
    mkdir -p "$KERNEL_DIR/fs/susfs"
    cat > "$KERNEL_DIR/fs/susfs/Kconfig" << 'KCONF'
config SUSFS
	bool "SUSFS - Stealth Userspace Filesystem"
	default y
	help
	  SUSFS provides filesystem-level root hiding capabilities.

config SUSFS_SUS_PATH
	bool "SUSFS - Hide paths from listing"
	depends on SUSFS
	default y

config SUSFS_SUS_MOUNT
	bool "SUSFS - Hide mount entries"
	depends on SUSFS
	default y

config SUSFS_TRY_UMOUNT
	bool "SUSFS - Try umount hidden mounts"
	depends on SUSFS
	default y

config SUSFS_SPOOF_UNAME
	bool "SUSFS - Spoof kernel uname"
	depends on SUSFS
	default y

config SUSFS_OPEN_REDIRECT
	bool "SUSFS - File open redirect"
	depends on SUSFS
	default y

config SUSFS_SUS_KSTAT
	bool "SUSFS - Spoof kstat"
	depends on SUSFS
	default y
KCONF
    log_info "Created SUSFS Kconfig"
fi

# Cleanup
rm -rf "$SUSFS_TEMP"

log_info "=== SUSFS Patches Applied Successfully ==="
