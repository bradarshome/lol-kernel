#!/bin/bash
# ============================================
# LolKernel - Apply KernelSU Universal Driver
# ============================================
# Apply KernelSU kernel driver (universal, compatible with all forks)
# User pilih manager APK: KernelSU, KSU-Next, KowSU, SukiSU-Ultra
# Usage: ./apply_ksu.sh <kernel_version> <source_dir>

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

log_info "=== Applying KernelSU Driver ==="
log_info "Kernel Version: $KERNEL_VERSION"
log_info "Kernel Dir: $KERNEL_DIR"

# Check if KSU already applied
if [[ -d "$KERNEL_DIR/$KSU_DRIVER_PATH" ]]; then
    log_warn "KernelSU driver already exists at $KERNEL_DIR/$KSU_DRIVER_PATH"
    read -p "Re-apply? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping KernelSU driver."
        exit 0
    fi
    rm -rf "$KERNEL_DIR/$KSU_DRIVER_PATH"
fi

# Clone KernelSU
KSU_TEMP="$PROJECT_DIR/tmp/KernelSU"
rm -rf "$KSU_TEMP"
log_info "Cloning KernelSU driver..."
git clone --depth=1 -b "$KSU_BRANCH" "$KSU_REPO" "$KSU_TEMP"

# Copy kernel driver
log_info "Installing KernelSU driver..."
mkdir -p "$KERNEL_DIR/$KSU_DRIVER_PATH"
cp -r "$KSU_TEMP/kernel/"* "$KERNEL_DIR/$KSU_DRIVER_PATH/"

# Integrate into kernel build system
log_info "Integrating KernelSU into build system..."

# Add to drivers/Makefile
DRIVERS_MAKEFILE="$KERNEL_DIR/drivers/Makefile"
if ! grep -q "kernelsu" "$DRIVERS_MAKEFILE" 2>/dev/null; then
    echo "" >> "$DRIVERS_MAKEFILE"
    echo "# KernelSU" >> "$DRIVERS_MAKEFILE"
    echo "obj-\$(CONFIG_KSU) += kernelsu/" >> "$DRIVERS_MAKEFILE"
    log_info "Added KernelSU to drivers/Makefile"
fi

# Add to drivers/Kconfig
DRIVERS_KCONFIG="$KERNEL_DIR/drivers/Kconfig"
if [[ -f "$DRIVERS_KCONFIG" ]] && ! grep -q "kernelsu" "$DRIVERS_KCONFIG" 2>/dev/null; then
    # Insert before endmenu
    sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' "$DRIVERS_KCONFIG"
    log_info "Added KernelSU to drivers/Kconfig"
fi

# Create KernelSU Kconfig if not present
if [[ ! -f "$KERNEL_DIR/$KSU_DRIVER_PATH/Kconfig" ]]; then
    cat > "$KERNEL_DIR/$KSU_DRIVER_PATH/Kconfig" << 'KCONF'
config KSU
	bool "KernelSU - Kernel-based root solution"
	default y
	help
	  KernelSU provides kernel-level root access management.
	  Compatible with all KernelSU forks (Official, KSU-Next, KowSU, SukiSU-Ultra).
	  Users install their preferred manager APK on the device.
KCONF
    log_info "Created KernelSU Kconfig"
fi

# Patch init/Kconfig to add KSU option if using defconfig approach
INIT_KCONFIG="$KERNEL_DIR/init/Kconfig"
if [[ -f "$INIT_KCONFIG" ]] && ! grep -q "CONFIG_KSU" "$INIT_KCONFIG" 2>/dev/null; then
    log_info "KernelSU will be enabled via defconfig"
fi

# Cleanup
rm -rf "$KSU_TEMP"

log_info "=== KernelSU Driver Applied Successfully ==="
log_info ""
log_info "Compatible managers (install on device):"
log_info "  - KernelSU Official: https://github.com/tiann/KernelSU"
log_info "  - KSU-Next: https://github.com/KernelSU-Next/KernelSU-Next"
log_info "  - KowSU: https://github.com/KOWX712/KernelSU"
log_info "  - SukiSU-Ultra: https://github.com/SukiSU-Ultra/SukiSU-Ultra"
