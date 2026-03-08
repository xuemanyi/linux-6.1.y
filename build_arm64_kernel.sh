#!/usr/bin/env bash

set -e

# ======================================
# Linux Kernel ARM64 Build Script
# All build artifacts -> output/
# ======================================

KERNEL_DIR=$(pwd)
OUTPUT_DIR=$KERNEL_DIR/output

ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
JOBS=$(nproc)

echo "======================================"
echo " ARM64 Kernel Build Script"
echo "--------------------------------------"
echo "KERNEL_DIR=$KERNEL_DIR"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "ARCH=$ARCH"
echo "CROSS_COMPILE=$CROSS_COMPILE"
echo "JOBS=$JOBS"
echo "======================================"

# --------------------------------------
# Check toolchain
# --------------------------------------

if ! command -v ${CROSS_COMPILE}gcc >/dev/null 2>&1; then
    echo "ERROR: ${CROSS_COMPILE}gcc not found!"
    echo "Install toolchain:"
    echo "sudo apt install gcc-aarch64-linux-gnu"
    exit 1
fi

echo "[OK] Toolchain found: $(which ${CROSS_COMPILE}gcc)"

# --------------------------------------
# 1 Clean source tree
# --------------------------------------

echo
echo "[1/6] Cleaning kernel source tree..."
make ARCH=$ARCH mrproper

# --------------------------------------
# 2 Remove old output
# --------------------------------------

echo
echo "[2/6] Cleaning output directory..."

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# --------------------------------------
# 3 Generate default config
# --------------------------------------

echo
echo "[3/6] Generating default ARM64 config..."

make O=$OUTPUT_DIR \
    ARCH=$ARCH \
    CROSS_COMPILE=$CROSS_COMPILE \
    defconfig

# --------------------------------------
# 4 Build kernel
# --------------------------------------

echo
echo "[4/6] Building kernel (Image, modules, dtbs)..."

make -j$JOBS \
    O=$OUTPUT_DIR \
    ARCH=$ARCH \
    CROSS_COMPILE=$CROSS_COMPILE \
    Image modules dtbs vmlinux

# --------------------------------------
# 5 Install modules
# --------------------------------------

echo
echo "[5/6] Installing kernel modules..."

make O=$OUTPUT_DIR \
    ARCH=$ARCH \
    CROSS_COMPILE=$CROSS_COMPILE \
    INSTALL_MOD_PATH=$OUTPUT_DIR \
    modules_install

# --------------------------------------
# 6 Done
# --------------------------------------

echo
echo "[6/6] Build finished successfully!"
echo

echo "======================================"
echo " Build Artifacts Location"
echo "--------------------------------------"
echo "Kernel Image:"
echo "  $OUTPUT_DIR/arch/arm64/boot/Image"
echo
echo "Device Tree (DTB):"
echo "  $OUTPUT_DIR/arch/arm64/boot/dts/"
echo
echo "Kernel Modules:"
echo "  $OUTPUT_DIR/lib/modules/"
echo
echo "vmlinux:"
echo "  $OUTPUT_DIR/vmlinux"
echo
echo "System.map:"
echo "  $OUTPUT_DIR/System.map"
echo
echo "Kernel config:"
echo "  $OUTPUT_DIR/.config"
echo "======================================"
