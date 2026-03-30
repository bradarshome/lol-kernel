#!/bin/bash
# ============================================
# LolKernel - Apply Zygisk Injection Support
# ============================================
# Apply patches untuk Zygisk/zygote injection support
# Usage: ./apply_zygisk.sh <kernel_version> <source_dir>

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

log_info "=== Applying Zygisk Injection Support ==="
log_info "Kernel Version: $KERNEL_VERSION"

# Zygisk patch directory
ZYGIKS_PATCH_DIR="$PROJECT_DIR/patches/zygisk"
ZYGIKS_APPLIED=0

# Apply custom Zygisk patches if available
if [[ -d "$ZYGIKS_PATCH_DIR" ]]; then
    cd "$KERNEL_DIR"
    for patch_file in "$ZYGIKS_PATCH_DIR"/*.patch; do
        [[ -f "$patch_file" ]] || continue

        patch_name=$(basename "$patch_file")
        log_info "Applying Zygisk patch: $patch_name"

        if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>/dev/null; then
            ZYGIKS_APPLIED=$((ZYGIKS_APPLIED + 1))
        else
            log_warn "Patch $patch_name may have failed (possibly already applied)"
        fi
    done
else
    log_info "No custom Zygisk patches found at $ZYGIKS_PATCH_DIR"
fi

# KernelSU already provides zygisk injection support via its driver
# Check if KSU has zygisk support built-in
if [[ -f "$KERNEL_DIR/$KSU_DRIVER_PATH/zygisk.c" ]] || [[ -f "$KERNEL_DIR/$KSU_DRIVER_PATH/zygisk.h" ]]; then
    log_info "Zygisk support found in KernelSU driver"
else
    log_warn "Zygisk not found in KernelSU driver"
    log_warn "Ensure your KernelSU fork supports Zygisk injection"
fi

# Add Zygisk Kconfig option
ZYGIKS_KCONFIG="$KERNEL_DIR/$KSU_DRIVER_PATH/Kconfig"
if [[ -f "$ZYGIKS_KCONFIG" ]] && ! grep -q "ZYGIKS" "$ZYGIKS_KCONFIG" 2>/dev/null; then
    cat >> "$ZYGIKS_KCONFIG" << 'KCONF'

config KSU_ZYGISK
	bool "KernelSU - Zygisk injection support"
	depends on KSU
	default y
	help
	  Enable Zygisk (Zygote injection) support in KernelSU.
	  This allows module injection into the Zygote process.
	  Required for modules that modify app behavior.
KCONF
    log_info "Added Zygisk Kconfig option"
fi

log_info "=== Zygisk Support Configured ==="
log_info "Applied $ZYGIKS_APPLIED custom patch(es)"
