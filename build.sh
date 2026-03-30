#!/bin/bash
# ============================================
#       _ _    _                 _ _
#      | | |  | |               | (_)
#      | | |  | | __ _ _ __   __| |_ _ __   __ _
#  _   | | |  | |/ _` | '_ \ / _` | | '_ \ / _` |
# | |__| | |__| | (_| | | | | (_| | | | | | (_| |
#  \____/ \____/ \__,_|_| |_|\__,_|_|_| |_|\__, |
#                                            __/ |
#  GKI Universal Kernel with KernelSU       |___/
#  + SUSFS + Zygisk + AnyKernel3
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================
# Banner
# ============================================
show_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║                                              ║"
    echo "  ║   _ _    _                 _ _              ║"
    echo "  ║  | | |  | |               | (_)             ║"
    echo "  ║  | | |  | | __ _ _ __   __| |_ _ __   __ _  ║"
    echo "  ║  _   | | |  | |/ _\` | '_ \\ / _\` | | '_ \\ / _\`| ║"
    echo "  ║ | |__| | |__| | (_| | | | | (_| | | | | | (_| |║"
    echo "  ║  \\____/ \\____/ \\__,_|_| |_|\\__,_|_|_| |_|\\__, |║"
    echo "  ║                                            __/ |║"
    echo "  ║                                           |___/ ║"
    echo "  ║                                              ║"
    echo "  ║   GKI Universal Kernel                       ║"
    echo "  ║   KernelSU + SUSFS + Zygisk + AnyKernel3    ║"
    echo "  ║                                              ║"
    echo "  ║   v${PROJECT_VERSION} by ${PROJECT_AUTHOR}                        ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ============================================
# Menu
# ============================================
show_menu() {
    echo -e "${BOLD}Build Options:${NC}"
    echo ""
    echo "  1) Build Kernel 5.10 (Android 12)"
    echo "  2) Build Kernel 6.6 (Android 15)"
    echo "  3) Build All Versions"
    echo ""
    echo -e "${BOLD}Utilities:${NC}"
    echo ""
    echo "  4) Setup Source Only (download kernel source)"
    echo "  5) Apply Patches Only (SUSFS + KSU + Zygisk)"
    echo "  6) Clean Build"
    echo "  7) Docker Build Environment"
    echo ""
    echo "  0) Exit"
    echo ""
    read -p "Pilih opsi [0-7]: " choice
    echo "$choice"
}

# ============================================
# Build single kernel version
# ============================================
build_kernel_version() {
    local KERNEL_VERSION="$1"
    local SOURCE_DIR="$SCRIPT_DIR/kernel-source/$KERNEL_VERSION"

    log_info "========================================"
    log_info "Building LolKernel for Android ${KERNEL_VERSION}"
    log_info "========================================"

    # Step 1: Check/setup source
    if [[ ! -d "$SOURCE_DIR/common" ]]; then
        log_step "Step 1/6: Setting up kernel source..."
        bash "$SCRIPT_DIR/scripts/setup_source.sh" "$KERNEL_VERSION"
    else
        log_step "Step 1/6: Source exists, skipping setup"
    fi

    # Step 2: Apply SUSFS patches
    log_step "Step 2/6: Applying SUSFS patches..."
    bash "$SCRIPT_DIR/scripts/apply_susfs.sh" "$KERNEL_VERSION" "$SOURCE_DIR"

    # Step 3: Apply KernelSU driver
    log_step "Step 3/6: Applying KernelSU driver..."
    bash "$SCRIPT_DIR/scripts/apply_ksu.sh" "$KERNEL_VERSION" "$SOURCE_DIR"

    # Step 4: Apply Zygisk support
    log_step "Step 4/6: Applying Zygisk support..."
    bash "$SCRIPT_DIR/scripts/apply_zygisk.sh" "$KERNEL_VERSION" "$SOURCE_DIR"

    # Step 5: Build kernel
    log_step "Step 5/6: Building kernel..."
    bash "$SCRIPT_DIR/scripts/build_kernel.sh" "$KERNEL_VERSION" "$SOURCE_DIR"

    # Step 6: Pack AnyKernel3 flashable zip
    local BUILD_OUT="$SCRIPT_DIR/$OUTPUT_DIR/$KERNEL_VERSION"
    log_step "Step 6/6: Packing AnyKernel3 flashable zip..."
    bash "$SCRIPT_DIR/scripts/pack_anykernel3.sh" "$KERNEL_VERSION" "$BUILD_OUT"

    log_info "========================================"
    log_info "Build complete for Android ${KERNEL_VERSION}!"
    log_info "========================================"
    log_info "Output: $SCRIPT_DIR/$OUTPUT_DIR/"
    ls -lh "$SCRIPT_DIR/$OUTPUT_DIR/"*.zip 2>/dev/null || true
}

# ============================================
# Clean build
# ============================================
clean_build() {
    log_warn "Cleaning build artifacts..."
    rm -rf "$SCRIPT_DIR/$OUTPUT_DIR"
    rm -rf "$SCRIPT_DIR/tmp"
    rm -rf "$SCRIPT_DIR/kernel-source"
    log_info "Clean complete!"
}

# ============================================
# Docker build
# ============================================
docker_build() {
    log_info "Building Docker image..."
    docker build -t "$DOCKER_IMAGE:$DOCKER_TAG" "$SCRIPT_DIR/docker/"
    log_info "Docker image built: $DOCKER_IMAGE:$DOCKER_TAG"
    log_info ""
    log_info "Run with:"
    log_info "  docker run -it --rm \\"
    log_info "    -v \$(pwd):/build \\"
    log_info "    -v \$(pwd)/kernel-source:/build/kernel-source \\"
    log_info "    $DOCKER_IMAGE:$DOCKER_TAG ./build.sh"
}

# ============================================
# Main
# ============================================
main() {
    show_banner

    # If argument provided, run directly
    case "${1:-}" in
        "5.10")
            build_kernel_version "5.10"
            exit 0
            ;;
        "6.6")
            build_kernel_version "6.6"
            exit 0
            ;;
        "all")
            for ver in "${KERNEL_VERSIONS[@]}"; do
                build_kernel_version "$ver"
            done
            exit 0
            ;;
        "clean")
            clean_build
            exit 0
            ;;
        "docker")
            docker_build
            exit 0
            ;;
    esac

    # Interactive menu
    while true; do
        choice=$(show_menu)

        case "$choice" in
            1)
                build_kernel_version "5.10"
                ;;
            2)
                build_kernel_version "6.6"
                ;;
            3)
                for ver in "${KERNEL_VERSIONS[@]}"; do
                    build_kernel_version "$ver"
                done
                ;;
            4)
                echo ""
                read -p "Kernel version (5.10/6.6): " ver
                bash "$SCRIPT_DIR/scripts/setup_source.sh" "$ver"
                ;;
            5)
                echo ""
                read -p "Kernel version (5.10/6.6): " ver
                SOURCE_DIR="$SCRIPT_DIR/kernel-source/$ver"
                bash "$SCRIPT_DIR/scripts/apply_susfs.sh" "$ver" "$SOURCE_DIR"
                bash "$SCRIPT_DIR/scripts/apply_ksu.sh" "$ver" "$SOURCE_DIR"
                bash "$SCRIPT_DIR/scripts/apply_zygisk.sh" "$ver" "$SOURCE_DIR"
                ;;
            6)
                clean_build
                ;;
            7)
                docker_build
                ;;
            0)
                log_info "Bye!"
                exit 0
                ;;
            *)
                log_error "Invalid option!"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
        echo ""
    done
}

main "$@"
