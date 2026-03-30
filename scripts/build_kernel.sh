#!/bin/bash
# ============================================
# LolKernel - Build Kernel with Bazel
# ============================================
# Build GKI kernel menggunakan Bazel
# Usage: ./build_kernel.sh <kernel_version> <source_dir>

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
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

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

log_info "=== $PROJECT_NAME Build Process ==="
log_info "Kernel Version: $KERNEL_VERSION"
log_info "Source Dir: $SOURCE_DIR"
log_info "Build Jobs: $BUILD_JOBS"

# Output directory
BUILD_OUT="$PROJECT_DIR/$OUTPUT_DIR/$KERNEL_VERSION"
mkdir -p "$BUILD_OUT"

# --- Step 1: Configure Kernel ---
log_step "1/4 Configuring kernel..."

cd "$KERNEL_DIR"

# Generate defconfig with custom options
DEFCONFIG="gki_defconfig"
if [[ ! -f "arch/arm64/configs/$DEFCONFIG" ]]; then
    # Try alternative names
    for alt in "gki_defconfig" "android14-6.1_gki_defconfig" "android15-6.6_gki_defconfig"; do
        if [[ -f "arch/arm64/configs/$alt" ]]; then
            DEFCONFIG="$alt"
            break
        fi
    done
fi

log_info "Using defconfig: $DEFCONFIG"

# Create custom config fragment
CUSTOM_CONFIG="$BUILD_OUT/custom.config"
cat > "$CUSTOM_CONFIG" << CONF
# Kernel Version String
CONFIG_LOCALVERSION="-$PROJECT_NAME"

# KernelSU
CONFIG_KSU=y

# SUSFS
CONFIG_SUSFS=y
CONFIG_SUSFS_SUS_PATH=y
CONFIG_SUSFS_SUS_MOUNT=y
CONFIG_SUSFS_TRY_UMOUNT=y
CONFIG_SUSFS_SPOOF_UNAME=y
CONFIG_SUSFS_OPEN_REDIRECT=y
CONFIG_SUSFS_SUS_KSTAT=y

# Zygisk support
CONFIG_KSU_ZYGISK=y

# LolPerf - Smart Performance Manager
CONFIG_LOLPERF=y

# Required for KSU compatibility
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONF

# Apply defconfig
if command -v make &>/dev/null; then
    make ARCH=arm64 "$DEFCONFIG" 2>/dev/null || true

    # Merge custom config
    if [[ -f ".config" ]]; then
        log_info "Merging custom config options..."
        while IFS= read -r line; do
            [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
            key="${line%%=*}"
            # Replace or append config
            if grep -q "^${key}=" .config 2>/dev/null; then
                sed -i "s|^${key}=.*|${line}|" .config
            elif grep -q "^# ${key} is not set" .config 2>/dev/null; then
                sed -i "s|^# ${key} is not set|${line}|" .config
            else
                echo "$line" >> .config
            fi
        done < "$CUSTOM_CONFIG"

        # Run olddefconfig to resolve dependencies
        make ARCH=arm64 olddefconfig 2>/dev/null || true
    fi
else
    log_warn "make not found, skipping defconfig (will be handled by Bazel)"
fi

# --- Step 2: Build with Bazel ---
log_step "2/4 Building kernel with Bazel..."

cd "$SOURCE_DIR"

# Check if Bazel build file exists
if [[ -f "common/BUILD.bazel" ]]; then
    log_info "Using Bazel build system (GKI 2.0)"

    # Remove protected_exports if present (fixes Wi-Fi/BT issues)
    if grep -q "protected_exports" common/BUILD.bazel 2>/dev/null; then
        log_info "Removing protected_exports for compatibility..."
        sed -i '/protected_exports/d' common/BUILD.bazel
    fi

    # Build with Bazel
    bazel run \
        --config=fast \
        --config=stamp \
        --lto="$LTO_MODE" \
        //common:kernel_aarch64_dist \
        2>&1 | tee "$BUILD_OUT/build.log"

    # Find build output
    BAZEL_OUT=$(find . -path "*/bazel-out/*/bin/common/kernel_aarch64/*" -name "Image" 2>/dev/null | head -1)
    if [[ -n "$BAZEL_OUT" ]]; then
        BAZEL_DIR=$(dirname "$BAZEL_OUT")
        cp "$BAZEL_DIR/Image" "$BUILD_OUT/Image" 2>/dev/null || true
        cp "$BAZEL_DIR/Image.gz" "$BUILD_OUT/Image.gz" 2>/dev/null || true
        log_info "Bazel output copied to $BUILD_OUT"
    fi

elif [[ -f "Makefile" || -f "common/Makefile" ]]; then
    log_info "Using Make build system"

    # Ensure we're in the kernel directory (common/)
    if [[ -f "common/Makefile" ]]; then
        cd "$KERNEL_DIR"
    fi

    # Set cross-compile variables
    export ARCH=arm64
    export SUBARCH=arm64

    # Try to find clang
    if command -v clang &>/dev/null; then
        export CC=clang
        export HOSTCC=clang
        export HOSTCXX=clang++
        log_info "Using Clang: $(clang --version | head -1)"
    fi

    # Build Image
    make -j"$BUILD_JOBS" Image 2>&1 | tee "$BUILD_OUT/build.log"

    # Copy output
    if [[ -f "arch/arm64/boot/Image" ]]; then
        cp arch/arm64/boot/Image "$BUILD_OUT/Image"
    fi
    if [[ -f "arch/arm64/boot/Image.gz" ]]; then
        cp arch/arm64/boot/Image.gz "$BUILD_OUT/Image.gz"
    fi

else
    log_error "No build system found! Expected BUILD.bazel or Makefile"
    exit 1
fi

# --- Step 3: Verify Build Output ---
log_step "3/4 Verifying build output..."

if [[ -f "$BUILD_OUT/Image" || -f "$BUILD_OUT/Image.gz" ]]; then
    log_info "Build successful!"
    [[ -f "$BUILD_OUT/Image" ]] && log_info "Image: $BUILD_OUT/Image ($(du -sh "$BUILD_OUT/Image" | cut -f1))"
    [[ -f "$BUILD_OUT/Image.gz" ]] && log_info "Image.gz: $BUILD_OUT/Image.gz ($(du -sh "$BUILD_OUT/Image.gz" | cut -f1))"
else
    log_error "Build failed! No kernel Image found."
    log_error "Check build log: $BUILD_OUT/build.log"
    exit 1
fi

# --- Step 4: Save Build Info ---
log_step "4/4 Saving build info..."

BUILD_INFO="$BUILD_OUT/build_info.txt"
cat > "$BUILD_INFO" << INFO
$PROJECT_NAME Build Information
===============================
Project: $PROJECT_NAME v$PROJECT_VERSION
Kernel Version: $KERNEL_VERSION
Build Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Build Host: $(hostname)
KernelSU: $KSU_BRANCH
SUSFS: Included
Zygisk: Supported
Arch: arm64 (Universal GKI)
INFO

log_info "Build info saved to $BUILD_INFO"

log_info "=== Build Complete ==="
log_info "Output directory: $BUILD_OUT"
