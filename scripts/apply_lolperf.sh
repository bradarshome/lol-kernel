#!/bin/bash
# ============================================
# Apply LolPerf - Smart Performance Manager
# ============================================
# Copy lolperf kernel module ke kernel source
# Usage: ./apply_lolperf.sh <kernel_version> <source_dir>

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

log_info "=== Applying LolPerf Module ==="
log_info "Kernel Version: $KERNEL_VERSION"

LOLPERF_PATCH_DIR="$PROJECT_DIR/patches/lolperf"
LOLPERF_TARGET="$KERNEL_DIR/drivers/misc/lolperf"

# Check if module already applied
if [[ -d "$LOLPERF_TARGET" ]]; then
    log_warn "LolPerf module already exists, re-applying..."
    rm -rf "$LOLPERF_TARGET"
fi

# Copy module source
log_info "Copying LolPerf module source..."
mkdir -p "$LOLPERF_TARGET"
cp "$LOLPERF_PATCH_DIR/lolperf.c" "$LOLPERF_TARGET/"
cp "$LOLPERF_PATCH_DIR/lolperf.h" "$LOLPERF_TARGET/"
cp "$LOLPERF_PATCH_DIR/lolperf_battery.c" "$LOLPERF_TARGET/"
cp "$LOLPERF_PATCH_DIR/lolperf_gaming.c" "$LOLPERF_TARGET/"
cp "$LOLPERF_PATCH_DIR/Kconfig" "$LOLPERF_TARGET/"
cp "$LOLPERF_PATCH_DIR/Makefile" "$LOLPERF_TARGET/"

# Integrate into drivers/misc/Makefile
DRIVERS_MISC_MAKEFILE="$KERNEL_DIR/drivers/misc/Makefile"
if [[ -f "$DRIVERS_MISC_MAKEFILE" ]] && ! grep -q "lolperf" "$DRIVERS_MISC_MAKEFILE" 2>/dev/null; then
    echo "" >> "$DRIVERS_MISC_MAKEFILE"
    echo "# LolPerf - Smart Performance Manager" >> "$DRIVERS_MISC_MAKEFILE"
    echo "obj-\$(CONFIG_LOLPERF) += lolperf/" >> "$DRIVERS_MISC_MAKEFILE"
    log_info "Added LolPerf to drivers/misc/Makefile"
fi

# Integrate into drivers/misc/Kconfig
DRIVERS_MISC_KCONFIG="$KERNEL_DIR/drivers/misc/Kconfig"
if [[ -f "$DRIVERS_MISC_KCONFIG" ]] && ! grep -q "lolperf" "$DRIVERS_MISC_KCONFIG" 2>/dev/null; then
    sed -i '/^endmenu$/i source "drivers/misc/lolperf/Kconfig"' "$DRIVERS_MISC_KCONFIG"
    log_info "Added LolPerf to drivers/misc/Kconfig"
fi

log_info "=== LolPerf Module Applied Successfully ==="
log_info ""
log_info "After build, interface will be available at:"
log_info "  /sys/kernel/lolperf/profile"
log_info "  /sys/kernel/lolperf/auto_mode"
log_info "  /sys/kernel/lolperf/gaming_detect"
log_info "  /sys/kernel/lolperf/status"
