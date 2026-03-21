#!/usr/bin/env bash

set -euo pipefail

# ======================================
# Linux Kernel ARM64 Build Script
#
# Features:
#   - Compiler mode:
#       1) gcc
#       2) clang
#   - compile_commands.json mode:
#       1) none
#       2) bear
#       3) kernel (make compile_commands.json, fallback to kernel script)
#   - Interactive mode when no args are passed
#   - Separate output dirs for gcc / clang
#   - Build logs
#   - menuconfig / savedefconfig support
# ======================================

KERNEL_DIR=$(pwd)
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"
JOBS="${JOBS:-$(nproc)}"

DEFAULT_BUILD_TARGETS=("Image" "modules" "dtbs" "vmlinux")
DEFAULT_COMPILER_MODE="gcc"
DEFAULT_CCDB_MODE="none"

OUTPUT_DIR_GCC="$KERNEL_DIR/output-gcc"
OUTPUT_DIR_CLANG="$KERNEL_DIR/output-clang"

LOG_DIR="$KERNEL_DIR/build-logs"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"

COMPILER_MODE=""
CCDB_MODE=""
BUILD_TARGETS=()
OUTPUT_DIR=""
BUILD_LOG=""

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
  $0 [COMPILER_MODE] [CCDB_MODE] [MAKE_TARGETS...]

COMPILER_MODE:
  gcc
  clang

CCDB_MODE:
  none
  bear
  kernel

Examples:
  $0
      # interactive mode

  $0 gcc
      # gcc + no compile_commands.json, default targets

  $0 clang
      # clang + no compile_commands.json, default targets

  $0 gcc kernel
      # gcc + kernel-native compile_commands.json generation

  $0 clang bear
      # clang + bear generate compile_commands.json

  $0 clang kernel Image modules dtbs vmlinux

  $0 gcc none menuconfig

Notes:
  1) If COMPILER_MODE is not provided, interactive selection will be shown.
  2) If CCDB_MODE is not provided, default is: $DEFAULT_CCDB_MODE
  3) If MAKE_TARGETS are not provided, default targets are used:
     ${DEFAULT_BUILD_TARGETS[*]}
EOF
}

interactive_select_compiler() {
    echo
    echo "请选择编译器："
    echo "  1) gcc"
    echo "  2) clang"
    echo

    while true; do
        read -rp "输入选项 [1-2] (默认 1): " choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                COMPILER_MODE="gcc"
                break
                ;;
            2)
                COMPILER_MODE="clang"
                break
                ;;
            *)
                echo "无效输入，请重新选择。"
                ;;
        esac
    done
}

interactive_select_ccdb() {
    echo
    echo "请选择 compile_commands.json 生成方式："
    echo "  1) none   (不生成)"
    echo "  2) bear   (使用 bear 捕获编译命令)"
    echo "  3) kernel (使用 make compile_commands.json；失败时回退到内核脚本)"
    echo

    while true; do
        read -rp "输入选项 [1-3] (默认 1): " choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                CCDB_MODE="none"
                break
                ;;
            2)
                CCDB_MODE="bear"
                break
                ;;
            3)
                CCDB_MODE="kernel"
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
    if [[ $# -eq 0 ]]; then
        interactive_select_compiler
        interactive_select_ccdb
        interactive_select_targets
        return
    fi

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        gcc|clang)
            COMPILER_MODE="$1"
            shift
            ;;
        *)
            echo "未检测到合法 COMPILER_MODE，进入交互模式。"
            interactive_select_compiler
            interactive_select_ccdb
            interactive_select_targets
            return
            ;;
    esac

    case "${1:-}" in
        none|bear|kernel)
            CCDB_MODE="$1"
            shift
            ;;
        "")
            CCDB_MODE="$DEFAULT_CCDB_MODE"
            ;;
        *)
            CCDB_MODE="$DEFAULT_CCDB_MODE"
            ;;
    esac

    if [[ $# -gt 0 ]]; then
        BUILD_TARGETS=("$@")
    else
        BUILD_TARGETS=("${DEFAULT_BUILD_TARGETS[@]}")
    fi
}

set_output_dir_by_mode() {
    case "$COMPILER_MODE" in
        gcc)
            OUTPUT_DIR="$OUTPUT_DIR_GCC"
            ;;
        clang)
            OUTPUT_DIR="$OUTPUT_DIR_CLANG"
            ;;
        *)
            echo "ERROR: Unsupported compiler mode: $COMPILER_MODE"
            exit 1
            ;;
    esac
}

prepare_log_file() {
    mkdir -p "$LOG_DIR"
    BUILD_LOG="$LOG_DIR/${COMPILER_MODE}-${CCDB_MODE}-${TIMESTAMP}.log"
}

check_kernel_tree() {
    echo
    echo "[Check] Verifying kernel source tree..."

    if [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
        echo "ERROR: Makefile not found in $KERNEL_DIR"
        echo "Please run this script from the Linux kernel source root."
        exit 1
    fi

    if ! grep -q "VERSION =" "$KERNEL_DIR/Makefile" 2>/dev/null; then
        echo "WARNING: Current directory may not be a standard kernel source tree."
    fi

    echo "[OK] Kernel source tree detected."
}

check_tools() {
    echo
    echo "[Check] Checking required tools..."

    local tool
    for tool in make grep rm mkdir nproc tee python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: Required tool '$tool' not found!"
            exit 1
        fi
    done

    if [[ "$COMPILER_MODE" == "gcc" ]]; then
        if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
            echo "ERROR: ${CROSS_COMPILE}gcc not found!"
            echo "Install with:"
            echo "  sudo apt install gcc-aarch64-linux-gnu"
            exit 1
        fi
        echo "[OK] GCC toolchain found: $(command -v "${CROSS_COMPILE}gcc")"
    fi

    if [[ "$COMPILER_MODE" == "clang" ]]; then
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

        echo "[OK] clang found: $(command -v clang)"
        echo "[OK] ld.lld found: $(command -v ld.lld)"
    fi

    if [[ "$CCDB_MODE" == "bear" ]]; then
        if ! command -v bear >/dev/null 2>&1; then
            echo "ERROR: bear not found!"
            echo "Install with:"
            echo "  sudo apt install bear"
            exit 1
        fi
        echo "[OK] bear found: $(command -v bear)"
    fi

    if [[ "$CCDB_MODE" == "kernel" ]]; then
        if [[ ! -f "$KERNEL_DIR/scripts/clang-tools/gen_compile_commands.py" ]]; then
            echo "WARNING: kernel script not found:"
            echo "  $KERNEL_DIR/scripts/clang-tools/gen_compile_commands.py"
            echo "kernel compile_commands fallback may be unavailable."
        else
            echo "[OK] kernel compile_commands helper found:"
            echo "     $KERNEL_DIR/scripts/clang-tools/gen_compile_commands.py"
        fi
    fi
}

warn_before_clean() {
    echo
    echo "[Info] About to run:"
    echo "  make ARCH=$ARCH mrproper"
    echo "This will clean the source tree."
    echo "If you have local config changes, back them up first."
}

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

run_make() {
    if [[ "$COMPILER_MODE" == "gcc" ]]; then
        kernel_make_gcc "$@"
    else
        kernel_make_clang "$@"
    fi
}

run_make_with_log() {
    if [[ "$COMPILER_MODE" == "gcc" ]]; then
        kernel_make_gcc "$@" 2>&1 | tee -a "$BUILD_LOG"
    else
        kernel_make_clang "$@" 2>&1 | tee -a "$BUILD_LOG"
    fi
}

clean_source_tree() {
    echo
    echo "[1/9] Cleaning kernel source tree..."
    make ARCH="$ARCH" mrproper
}

clean_output_dir() {
    echo
    echo "[2/9] Cleaning output directory..."
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
}

generate_defconfig() {
    echo
    echo "[3/9] Generating default ARM64 config..."
    run_make defconfig
}

handle_config_targets_if_needed() {
    local target

    for target in "${BUILD_TARGETS[@]}"; do
        case "$target" in
            menuconfig|xconfig|gconfig|nconfig|oldconfig|savedefconfig|defconfig)
                echo
                echo "[4/9] Running config target: $target"
                run_make "$target"

                if [[ "$target" == "savedefconfig" ]]; then
                    echo
                    echo "[Info] savedefconfig generated at:"
                    echo "  $OUTPUT_DIR/defconfig"
                fi

                echo
                echo "[DONE] Config target finished. No further build targets executed."
                print_summary
                exit 0
                ;;
        esac
    done
}

build_kernel() {
    echo
    echo "[5/9] Building kernel..."
    echo "COMPILER_MODE=$COMPILER_MODE"
    echo "CCDB_MODE=$CCDB_MODE"
    echo "OUTPUT_DIR=$OUTPUT_DIR"
    echo "BUILD_TARGETS=${BUILD_TARGETS[*]}"
    echo "BUILD_LOG=$BUILD_LOG"

    if [[ "$CCDB_MODE" == "bear" ]]; then
        if [[ "$COMPILER_MODE" == "gcc" ]]; then
            bear --output "$OUTPUT_DIR/compile_commands.json" -- \
                make -j"$JOBS" \
                    O="$OUTPUT_DIR" \
                    ARCH="$ARCH" \
                    CROSS_COMPILE="$CROSS_COMPILE" \
                    "${BUILD_TARGETS[@]}" 2>&1 | tee "$BUILD_LOG"
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
                    "${BUILD_TARGETS[@]}" 2>&1 | tee "$BUILD_LOG"
        fi
    else
        run_make_with_log -j"$JOBS" "${BUILD_TARGETS[@]}"
    fi
}

generate_compile_commands_kernel() {
    echo
    echo "[6/9] Generating compile_commands.json via kernel backend..."

    if [[ "$CCDB_MODE" != "kernel" ]]; then
        echo "[SKIP] CCDB_MODE is not 'kernel'"
        return
    fi

    rm -f "$OUTPUT_DIR/compile_commands.json"

    if run_make_with_log compile_commands.json; then
        if [[ -f "$OUTPUT_DIR/compile_commands.json" ]]; then
            echo "[OK] compile_commands.json generated by make target:"
            echo "  $OUTPUT_DIR/compile_commands.json"
            return
        fi
    fi

    echo "[WARN] make compile_commands.json failed or output missing."

    if [[ -f "$KERNEL_DIR/scripts/clang-tools/gen_compile_commands.py" ]]; then
        echo "[Info] Fallback to kernel script..."
        python3 "$KERNEL_DIR/scripts/clang-tools/gen_compile_commands.py" \
            -d "$OUTPUT_DIR" \
            -o "$OUTPUT_DIR/compile_commands.json" 2>&1 | tee -a "$BUILD_LOG"

        if [[ -f "$OUTPUT_DIR/compile_commands.json" ]]; then
            echo "[OK] compile_commands.json generated by kernel script:"
            echo "  $OUTPUT_DIR/compile_commands.json"
            return
        fi
    fi

    echo "ERROR: Failed to generate compile_commands.json with kernel backend."
    exit 1
}

check_compile_database() {
    echo
    echo "[7/9] Checking compile database..."

    if [[ "$CCDB_MODE" == "none" ]]; then
        echo "[SKIP] compile_commands.json generation disabled"
        return
    fi

    if [[ -f "$OUTPUT_DIR/compile_commands.json" ]]; then
        echo "[OK] compile_commands.json exists:"
        echo "  $OUTPUT_DIR/compile_commands.json"
    else
        echo "WARNING: compile_commands.json not found."
    fi
}

install_modules_if_needed() {
    local need_modules_install=0
    local target

    for target in "${BUILD_TARGETS[@]}"; do
        if [[ "$target" == "modules" || "$target" == "modules_install" ]]; then
            need_modules_install=1
            break
        fi
    done

    echo
    echo "[8/9] Installing kernel modules..."

    if [[ $need_modules_install -eq 0 ]]; then
        echo "[SKIP] 'modules' not in build targets, skip modules_install"
        return
    fi

    run_make_with_log INSTALL_MOD_PATH="$OUTPUT_DIR" modules_install
}

print_summary() {
    echo
    echo "[9/9] Build finished!"
    echo

    print_line
    echo " Build Summary"
    echo "--------------------------------------"
    echo "Compiler mode:"
    echo "  $COMPILER_MODE"
    echo
    echo "CCDB mode:"
    echo "  $CCDB_MODE"
    echo
    echo "Output dir:"
    echo "  $OUTPUT_DIR"
    echo
    echo "Build targets:"
    echo "  ${BUILD_TARGETS[*]:-N/A}"
    echo
    echo "Build log:"
    echo "  ${BUILD_LOG:-N/A}"
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

main() {
    print_header
    parse_input "$@"

    COMPILER_MODE="${COMPILER_MODE:-$DEFAULT_COMPILER_MODE}"
    CCDB_MODE="${CCDB_MODE:-$DEFAULT_CCDB_MODE}"

    set_output_dir_by_mode
    prepare_log_file

    echo
    echo "最终配置："
    echo "  COMPILER_MODE=$COMPILER_MODE"
    echo "  CCDB_MODE=$CCDB_MODE"
    echo "  OUTPUT_DIR=$OUTPUT_DIR"
    echo "  BUILD_TARGETS=${BUILD_TARGETS[*]}"
    echo "  BUILD_LOG=$BUILD_LOG"

    check_kernel_tree
    check_tools
    warn_before_clean
    clean_source_tree
    clean_output_dir
    generate_defconfig
    handle_config_targets_if_needed
    build_kernel
    generate_compile_commands_kernel
    check_compile_database
    install_modules_if_needed
    print_summary
}

main "$@"