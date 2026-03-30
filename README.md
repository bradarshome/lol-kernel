# LolKernel - GKI Universal Kernel

GKI (Generic Kernel Image) universal yang sudah terintegrasi dengan **KernelSU**, **SUSFS**, dan **Zygisk** support, dengan **AnyKernel3** untuk flashable zip.

## Features

- **Universal GKI** - Compatible dengan berbagai device Android (arm64)
- **KernelSU Universal** - Support semua fork (Official, KSU-Next, KowSU, SukiSU-Ultra)
- **SUSFS Integration** - Root hiding di filesystem level
- **Zygisk Support** - Module injection ke Zygote process
- **AnyKernel3** - Flashable zip untuk TWRP Recovery / KernelSU Manager
- **Docker Support** - Build environment siap pakai

## Supported Kernel Versions

| Version | Android | Branch |
|---------|---------|--------|
| 5.10 | Android 12 | `common-android12-5.10-lts` |
| 6.6 | Android 15 | `common-android15-6.6` |

## Quick Start

### 1. Build Semua Versi
```bash
chmod +x build.sh scripts/*.sh
./build.sh all
```

### 2. Build Spesifik Versi
```bash
./build.sh 5.10    # Android 12
./build.sh 6.6     # Android 15
```

### 3. Interactive Menu
```bash
./build.sh
```

### 4. Docker Build
```bash
./build.sh docker
docker run -it --rm \
  -v $(pwd):/build \
  -v $(pwd)/kernel-source:/build/kernel-source \
  lolkernel-builder ./build.sh all
```

## Project Structure

```
lol-kernel/
├── build.sh                    # Main build orchestrator
├── config.env                  # Build configuration
├── scripts/
│   ├── setup_source.sh         # Sync GKI kernel source
│   ├── apply_susfs.sh          # Apply SUSFS patches
│   ├── apply_ksu.sh            # Apply KernelSU driver
│   ├── apply_zygisk.sh         # Apply Zygisk patches
│   ├── build_kernel.sh         # Build kernel (Bazel)
│   ├── repack_boot.sh          # Repack boot.img
│   └── pack_anykernel3.sh      # Create flashable zip
├── patches/
│   ├── susfs/                  # Custom SUSFS patches
│   ├── zygisk/                 # Custom Zygisk patches
│   └── device/                 # Device-specific patches
├── docker/
│   └── Dockerfile              # Build environment
├── anykernel3/                 # AnyKernel3 template
└── output/                     # Build outputs
```

## Flash Methods

### Via TWRP Recovery
1. Copy `LolKernel-*-AnyKernel3.zip` ke device
2. Boot ke TWRP Recovery
3. Install → Pilih zip → Flash

### Via KernelSU Manager
1. Install KernelSU Manager APK di device
2. Open KernelSU Manager → Settings → Flash
3. Pilih `LolKernel-*-AnyKernel3.zip`

### Via Fastboot
```bash
# Extract boot.img from zip, then:
fastboot flash boot boot.img
fastboot reboot
```

## KernelSU Manager APKs

Kernel ini universal, install salah satu manager APK:

| Fork | APK |
|------|-----|
| KernelSU Official | [GitHub](https://github.com/tiann/KernelSU/releases) |
| KSU-Next | [GitHub](https://github.com/KernelSU-Next/KernelSU-Next/releases) |
| KowSU | [GitHub](https://github.com/KOWX712/KernelSU/releases) |
| SukiSU-Ultra | [GitHub](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases) |

## Dependencies (Local Build)

- Ubuntu 22.04+
- Git, Python 3, Bazel
- Clang/LLVM
- repo tool (Google)
- 50GB+ disk space
- 8GB+ RAM

## Credits

- [KernelSU](https://github.com/tiann/KernelSU) - Kernel-level root management
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu) - Filesystem-level root hiding
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) - Flashable zip template
- [Google AOSP](https://android.googlesource.com/) - GKI kernel source

## License

Kernel source: GPL-2.0
Build scripts: MIT
