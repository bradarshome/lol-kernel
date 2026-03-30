#!/bin/bash
# ============================================
# LolKernel - Apply SUSFS Kernel Patches
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

# Clone SUSFS
SUSFS_TEMP="$PROJECT_DIR/tmp/susfs4ksu"
rm -rf "$SUSFS_TEMP"
log_info "Cloning SUSFS patches..."
git clone --depth=1 "$SUSFS_REPO" "$SUSFS_TEMP"

# Determine SUSFS patch branch based on kernel version
case "$KERNEL_VERSION" in
    "5.10")
        SUSFS_PATCH_BRANCH="gki-android12-5.10"
        ;;
    "6.6")
        SUSFS_PATCH_BRANCH="gki-android15-6.6"
        ;;
    *)
        SUSFS_PATCH_BRANCH="gki-android14-6.1"
        ;;
esac

# Try to checkout the right branch, fallback to default
cd "$SUSFS_TEMP"
if git rev-parse --verify "$SUSFS_PATCH_BRANCH" &>/dev/null; then
    git checkout "$SUSFS_PATCH_BRANCH"
    log_info "Checked out branch: $SUSFS_PATCH_BRANCH"
else
    log_warn "Branch $SUSFS_PATCH_BRANCH not found, using default branch"
fi

# Step 1: Copy SUSFS filesystem code
log_info "Copying SUSFS filesystem patches..."
if [[ -d "kernel_patches/fs" ]]; then
    cp -r kernel_patches/fs/* "$KERNEL_DIR/fs/" 2>/dev/null || true
    log_info "Copied fs/ patches"
else
    log_warn "kernel_patches/fs not found, checking alternative paths..."
    # Some versions use different structure
    if [[ -d "fs" ]]; then
        cp -r fs/* "$KERNEL_DIR/fs/" 2>/dev/null || true
        log_info "Copied fs/ patches (alt path)"
    fi
fi

# Step 2: Copy SUSFS headers
log_info "Copying SUSFS headers..."
if [[ -d "kernel_patches/include/linux" ]]; then
    cp kernel_patches/include/linux/susfs* "$KERNEL_DIR/include/linux/" 2>/dev/null || true
    log_info "Copied include/linux/susfs* headers"
elif [[ -d "include/linux" ]]; then
    cp include/linux/susfs* "$KERNEL_DIR/include/linux/" 2>/dev/null || true
    log_info "Copied headers (alt path)"
fi

# Step 3: Apply patch files
log_info "Applying SUSFS version patches..."
cd "$KERNEL_DIR"

PATCHES_APPLIED=0
for patch_file in "$SUSFS_TEMP"/kernel_patches/*.patch "$SUSFS_TEMP"/*.patch; do
    [[ -f "$patch_file" ]] || continue

    patch_name=$(basename "$patch_file")
    log_info "Applying: $patch_name"

    if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>/dev/null; then
        PATCHES_APPLIED=$((PATCHES_APPLIED + 1))
    else
        log_warn "Patch $patch_name may have failed (possibly already applied)"
    fi
done

log_info "Applied $PATCHES_APPLIED SUSFS patch(es)"

# Step 4: Add SUSFS to Makefile/Kconfig
log_info "Integrating SUSFS into build system..."

# Add to fs/Makefile if not already present
FS_MAKEFILE="$KERNEL_DIR/fs/Makefile"
if ! grep -q "susfs" "$FS_MAKEFILE" 2>/dev/null; then
    echo "" >> "$FS_MAKEFILE"
    echo "# SUSFS" >> "$FS_MAKEFILE"
    echo "obj-\$(CONFIG_SUSFS) += susfs/" >> "$FS_MAKEFILE"
    log_info "Added SUSFS to fs/Makefile"
fi

# Add to fs/Kconfig if not already present
FS_KCONFIG="$KERNEL_DIR/fs/Kconfig"
if [[ -f "$FS_KCONFIG" ]] && ! grep -q "susfs" "$FS_KCONFIG" 2>/dev/null; then
    # Insert before the last 'endmenu' or at the end
    echo "" >> "$FS_KCONFIG"
    echo "source \"fs/susfs/Kconfig\"" >> "$FS_KCONFIG"
    log_info "Added SUSFS to fs/Kconfig"
fi

# Create SUSFS Kconfig if it exists in susfs dir
if [[ -f "$KERNEL_DIR/fs/susfs/Kconfig" ]]; then
    log_info "SUSFS Kconfig found"
else
    # Create a basic Kconfig for SUSFS
    mkdir -p "$KERNEL_DIR/fs/susfs"
    cat > "$KERNEL_DIR/fs/susfs/Kconfig" << 'KCONF'
config SUSFS
	bool "SUSFS - Stealth Userspace Filesystem"
	default y
	help
	  SUSFS provides filesystem-level root hiding capabilities.
	  Required for KernelSU root detection bypass.

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
