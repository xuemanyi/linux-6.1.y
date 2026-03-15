#!/usr/bin/env bash

set -euo pipefail

# ======================================
# Linux Kernel ARM64 Build Script
# Support:
#   1) gcc
#   2) bear-clang -> generate compile_commands.json
# If user passes args, use them directly
# If no args, provide interactive selection
# ======================================

KERNEL_DIR=$(pwd)
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
CLANG_TRIPLE=aarch64-linux-gnu-
JOBS=$(nproc)

# 默认构建目标
DEFAULT_BUILD_TARGETS=("Image" "modules" "dtbs" "vmlinux")

# 默认模式
DEFAULT_BUILD_MODE="gcc"

# 输出目录按模式隔离，避免互相污染
OUTPUT_DIR_GCC="$KERNEL_DIR/output-gcc"
OUTPUT_DIR_CLANG="$KERNEL_DIR/output-clang"

# --------------------------------------
# UI helpers
# --------------------------------------

print_line() {
    echo "======================================"
}

print_header() {
    print_line
    echo " ARM64 Kernel Build Script"
    echo "--------------------------------------"
    echo "KERNEL_DIR=$KERNEL_DIR"
    echo "ARCH=$ARCH"
    echo "CROSS_COMPILE=$CROSS_COMPILE"
    echo "CLANG_TRIPLE=$CLANG_TRIPLE"
    echo "JOBS=$JOBS"
    print_line
}

usage() {
    cat <<EOF
Usage:
  $0 [BUILD_MODE] [MAKE_TARGETS...]

BUILD_MODE:
  gcc
  bear-clang

Examples:
  $0
      # interactive mode

  $0 gcc
      # gcc mode, use default targets: ${DEFAULT_BUILD_TARGETS[*]}

  $0 bear-clang
      # bear+clang mode, generate compile_commands.json

  $0 gcc Image modules dtbs vmlinux

  $0 bear-clang menuconfig

Notes:
  1) If BUILD_MODE is not provided, interactive selection will be shown.
  2) If MAKE_TARGETS are not provided, default targets are used:
     ${DEFAULT_BUILD_TARGETS[*]}
EOF
}

# --------------------------------------
# Parse args or interactive select
# --------------------------------------

BUILD_MODE=""
BUILD_TARGETS=()

interactive_select_mode() {
    echo
    echo "请选择编译方式："
    echo "  1) gcc"
    echo "  2) bear-clang (生成 compile_commands.json 用于 AST 分析)"
    echo

    while true; do
        read -rp "输入选项 [1-2] (默认 1): " choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                BUILD_MODE="gcc"
                break
                ;;
            2)
                BUILD_MODE="bear-clang"
                break
                ;;
            *)
                echo "无效输入，请重新选择。"
                ;;
        esac
    done
}

interactive_select_targets() {
    echo
    echo "请选择编译目标："
    echo "  1) 默认目标: ${DEFAULT_BUILD_TARGETS[*]}"
    echo "  2) 自定义输入 make targets"
    echo

    while true; do
        read -rp "输入选项 [1-2] (默认 1): " choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                BUILD_TARGETS=("${DEFAULT_BUILD_TARGETS[@]}")
                break
                ;;
            2)
                read -rp "请输入 make targets（空格分隔），例如: Image modules dtbs vmlinux : " user_targets
                if [[ -z "${user_targets// }" ]]; then
                    echo "未输入任何 target，使用默认目标。"
                    BUILD_TARGETS=("${DEFAULT_BUILD_TARGETS[@]}")
                else
                    # shellcheck disable=SC2206
                    BUILD_TARGETS=($user_targets)
                fi
                break
                ;;
            *)
                echo "无效输入，请重新选择。"
                ;;
        esac
    done
}

parse_input() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            gcc|bear-clang)
                BUILD_MODE="$1"
                shift
                if [[ $# -gt 0 ]]; then
                    BUILD_TARGETS=("$@")
                else
                    BUILD_TARGETS=("${DEFAULT_BUILD_TARGETS[@]}")
                fi
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "未检测到合法 BUILD_MODE，进入交互模式。"
                interactive_select_mode
                interactive_select_targets
                ;;
        esac
    else
        interactive_select_mode
        interactive_select_targets
    fi
}

# --------------------------------------
# Select output dir
# --------------------------------------

set_output_dir_by_mode() {
    case "$BUILD_MODE" in
        gcc)
            OUTPUT_DIR="$OUTPUT_DIR_GCC"
            ;;
        bear-clang)
            OUTPUT_DIR="$OUTPUT_DIR_CLANG"
            ;;
        *)
            echo "ERROR: Unsupported build mode: $BUILD_MODE"
            exit 1
            ;;
    esac
}

# --------------------------------------
# Check toolchain
# --------------------------------------

check_tools() {
    echo
    echo "[Check] Checking toolchain..."

    if [[ "$BUILD_MODE" == "gcc" ]]; then
        if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
            echo "ERROR: ${CROSS_COMPILE}gcc not found!"
            echo "Install with:"
            echo "  sudo apt install gcc-aarch64-linux-gnu"
            exit 1
        fi
        echo "[OK] GCC toolchain found: $(which "${CROSS_COMPILE}gcc")"
    fi

    if [[ "$BUILD_MODE" == "bear-clang" ]]; then
        if ! command -v clang >/dev/null 2>&1; then
            echo "ERROR: clang not found!"
            echo "Install with:"
            echo "  sudo apt install clang"
            exit 1
        fi

        if ! command -v ld.lld >/dev/null 2>&1; then
            echo "ERROR: ld.lld not found!"
            echo "Install with:"
            echo "  sudo apt install lld"
            exit 1
        fi

        if ! command -v bear >/dev/null 2>&1; then
            echo "ERROR: bear not found!"
            echo "Install with:"
            echo "  sudo apt install bear"
            exit 1
        fi

        echo "[OK] clang found: $(which clang)"
        echo "[OK] ld.lld found: $(which ld.lld)"
        echo "[OK] bear found: $(which bear)"
    fi
}

# --------------------------------------
# Make helpers
# --------------------------------------

kernel_make_gcc() {
    make \
        O="$OUTPUT_DIR" \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        "$@"
}

kernel_make_clang() {
    make \
        O="$OUTPUT_DIR" \
        ARCH="$ARCH" \
        LLVM=1 \
        CC=clang \
        HOSTCC=clang \
        LD=ld.lld \
        HOSTLD=ld.lld \
        CLANG_TRIPLE="$CLANG_TRIPLE" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        "$@"
}

# --------------------------------------
# Build steps
# --------------------------------------

clean_source_tree() {
    echo
    echo "[1/7] Cleaning kernel source tree..."
    make ARCH="$ARCH" mrproper
}

clean_output_dir() {
    echo
    echo "[2/7] Cleaning output directory..."
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
}

generate_defconfig() {
    echo
    echo "[3/7] Generating default ARM64 config..."

    if [[ "$BUILD_MODE" == "gcc" ]]; then
        kernel_make_gcc defconfig
    else
        kernel_make_clang defconfig
    fi
}

build_kernel() {
    echo
    echo "[4/7] Building kernel..."
    echo "BUILD_MODE=$BUILD_MODE"
    echo "OUTPUT_DIR=$OUTPUT_DIR"
    echo "BUILD_TARGETS=${BUILD_TARGETS[*]}"

    if [[ "$BUILD_MODE" == "gcc" ]]; then
        kernel_make_gcc -j"$JOBS" "${BUILD_TARGETS[@]}"
    else
        bear --output "$OUTPUT_DIR/compile_commands.json" -- \
            make -j"$JOBS" \
                O="$OUTPUT_DIR" \
                ARCH="$ARCH" \
                LLVM=1 \
                CC=clang \
                HOSTCC=clang \
                LD=ld.lld \
                HOSTLD=ld.lld \
                CLANG_TRIPLE="$CLANG_TRIPLE" \
                CROSS_COMPILE="$CROSS_COMPILE" \
                "${BUILD_TARGETS[@]}"
    fi
}

install_modules_if_needed() {
    local need_modules_install=0

    for target in "${BUILD_TARGETS[@]}"; do
        if [[ "$target" == "modules" || "$target" == "modules_install" ]]; then
            need_modules_install=1
            break
        fi
    done

    echo
    echo "[5/7] Installing kernel modules..."

    if [[ $need_modules_install -eq 0 ]]; then
        echo "[SKIP] 'modules' not in build targets, skip modules_install"
        return
    fi

    if [[ "$BUILD_MODE" == "gcc" ]]; then
        kernel_make_gcc INSTALL_MOD_PATH="$OUTPUT_DIR" modules_install
    else
        kernel_make_clang INSTALL_MOD_PATH="$OUTPUT_DIR" modules_install
    fi
}

check_compile_database() {
    echo
    echo "[6/7] Checking compile database..."

    if [[ "$BUILD_MODE" == "bear-clang" ]]; then
        if [[ -f "$OUTPUT_DIR/compile_commands.json" ]]; then
            echo "[OK] compile_commands.json generated:"
            echo "  $OUTPUT_DIR/compile_commands.json"
        else
            echo "WARNING: compile_commands.json not found!"
            echo "Bear may miss some compile commands depending on build behavior."
        fi
    else
        echo "[SKIP] gcc mode does not generate compile_commands.json"
    fi
}

print_summary() {
    echo
    echo "[7/7] Build finished successfully!"
    echo

    print_line
    echo " Build Artifacts Location"
    echo "--------------------------------------"
    echo "Build mode:"
    echo "  $BUILD_MODE"
    echo
    echo "Output dir:"
    echo "  $OUTPUT_DIR"
    echo
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
    echo
    echo "compile_commands.json:"
    echo "  $OUTPUT_DIR/compile_commands.json"
    print_line
}

# --------------------------------------
# Main
# --------------------------------------

main() {
    print_header
    parse_input "$@"
    set_output_dir_by_mode

    echo
    echo "最终配置："
    echo "  BUILD_MODE=$BUILD_MODE"
    echo "  OUTPUT_DIR=$OUTPUT_DIR"
    echo "  BUILD_TARGETS=${BUILD_TARGETS[*]}"

    check_tools
    clean_source_tree
    clean_output_dir
    generate_defconfig
    build_kernel
    install_modules_if_needed
    check_compile_database
    print_summary
}

main "$@"