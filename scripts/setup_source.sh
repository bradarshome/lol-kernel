#!/bin/bash
# ============================================
# LolKernel - Setup GKI Kernel Source
# ============================================
# Sync kernel source dari Google AOSP
# Usage: ./setup_source.sh <kernel_version>
# Example: ./setup_source.sh 5.10

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

if [[ -z "$KERNEL_VERSION" ]]; then
    log_error "Usage: $0 <kernel_version>"
    log_error "Supported versions: 5.10, 6.6"
    exit 1
fi

# Map kernel version to AOSP branch
case "$KERNEL_VERSION" in
    "5.10")
        AOSP_BRANCH="common-android12-5.10-lts"
        ;;
    "6.6")
        AOSP_BRANCH="common-android15-6.6"
        ;;
    *)
        log_error "Unsupported kernel version: $KERNEL_VERSION"
        log_error "Supported: 5.10 (Android 12), 6.6 (Android 15)"
        exit 1
        ;;
esac

SOURCE_DIR="$PROJECT_DIR/kernel-source/$KERNEL_VERSION"

log_info "=== $PROJECT_NAME Source Setup ==="
log_info "Kernel Version: $KERNEL_VERSION"
log_info "AOSP Branch: $AOSP_BRANCH"
log_info "Source Dir: $SOURCE_DIR"

# Check if source already exists
if [[ -d "$SOURCE_DIR/common" ]]; then
    log_warn "Kernel source already exists at $SOURCE_DIR"
    read -p "Re-sync? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping sync. Using existing source."
        exit 0
    fi
fi

mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"

# Initialize repo
log_info "Initializing repo manifest..."
repo init -u "$AOSP_MANIFEST_URL" -b "$AOSP_BRANCH" --depth=3

# Sync source
log_info "Syncing kernel source (this may take a while)..."
repo sync -c --no-tags -j"$BUILD_JOBS"

# Verify
if [[ -d "common" ]]; then
    log_info "Kernel source synced successfully!"
    log_info "Source location: $SOURCE_DIR"
    log_info "Kernel common dir: $SOURCE_DIR/common"
else
    log_error "Sync failed! 'common' directory not found."
    exit 1
fi

log_info "=== Source Setup Complete ==="
