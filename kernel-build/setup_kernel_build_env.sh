#!/usr/bin/env bash

set -euo pipefail

# ======================================
# ARM64 Linux Kernel Build Environment Setup Script
#
# Support modes:
#   1) gcc
#   2) clang
#   3) all
#
# Features:
#   - Install required packages
#   - Verify toolchain availability
#   - Optionally persist environment variables into ~/.bashrc
#   - Compatible with build_kernel_arm64.sh
# ======================================

MODE="${1:-all}"

ARCH="arm64"
CROSS_COMPILE="aarch64-linux-gnu-"
CLANG_TRIPLE="aarch64-linux-gnu-"
BASHRC_FILE="${HOME}/.bashrc"

SUDO=""

print_line() {
    echo "======================================"
}

print_header() {
    print_line
    echo " ARM64 Kernel Build Environment Setup "
    echo "--------------------------------------"
    echo "MODE=$MODE"
    echo "ARCH=$ARCH"
    echo "CROSS_COMPILE=$CROSS_COMPILE"
    echo "CLANG_TRIPLE=$CLANG_TRIPLE"
    print_line
}

usage() {
    cat <<EOF
Usage:
  $0 [MODE]

MODE:
  gcc
  clang
  all

Examples:
  $0
      # install all dependencies

  $0 gcc
      # install gcc toolchain dependencies only

  $0 clang
      # install clang/llvm dependencies only

  $0 all
      # install both gcc and clang dependencies
EOF
}

check_mode() {
    case "$MODE" in
        gcc|clang|all)
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unsupported mode: $MODE"
            usage
            exit 1
            ;;
    esac
}

require_root_or_sudo() {
    if [[ "${EUID}" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "ERROR: sudo not found, please run as root or install sudo."
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo "ERROR: Cannot detect OS (/etc/os-release not found)."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"

    echo "[Info] Detected OS: ${PRETTY_NAME:-unknown}"
}

ensure_apt_based() {
    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" && "$OS_LIKE" != *"debian"* ]]; then
        echo "ERROR: This script currently supports Debian/Ubuntu only."
        echo "Please install dependencies manually on your distro."
        exit 1
    fi
}

apt_update_once() {
    echo
    echo "[1/6] Updating package index..."
    $SUDO apt update
}

install_common_packages() {
    echo
    echo "[2/6] Installing common build dependencies..."

    $SUDO apt install -y \
        build-essential \
        make \
        bc \
        bison \
        flex \
        libssl-dev \
        libelf-dev \
        dwarves \
        pahole \
        cpio \
        rsync \
        kmod \
        file \
        wget \
        curl \
        xz-utils \
        zstd \
        lz4 \
        python3 \
        python3-pip \
        python3-setuptools \
        pkg-config \
        git \
        unzip \
        ca-certificates \
        libncurses-dev
}

install_gcc_toolchain() {
    echo
    echo "[3/6] Installing GCC ARM64 cross toolchain..."

    $SUDO apt install -y \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu
}

install_clang_toolchain() {
    echo
    echo "[4/6] Installing Clang/LLVM toolchain..."

    $SUDO apt install -y \
        clang \
        lld \
        llvm \
        llvm-dev \
        clangd \
        bear
}

append_env_to_bashrc() {
    echo
    echo "[5/6] Configuring environment variables..."

    local marker_begin="# >>> arm64-kernel-build-env >>>"
    local marker_end="# <<< arm64-kernel-build-env <<<"

    touch "$BASHRC_FILE"

    if grep -Fq "$marker_begin" "$BASHRC_FILE"; then
        echo "[SKIP] Environment block already exists in $BASHRC_FILE"
        return
    fi

    cat >> "$BASHRC_FILE" <<EOF

$marker_begin
export ARCH=$ARCH
export CROSS_COMPILE=$CROSS_COMPILE
export CLANG_TRIPLE=$CLANG_TRIPLE
$marker_end
EOF

    echo "[OK] Appended environment variables to $BASHRC_FILE"
    echo "Run this after setup:"
    echo "  source \"$BASHRC_FILE\""
}

check_tools() {
    echo
    echo "[6/6] Verifying installed tools..."

    local failed=0
    local tool

    echo "--- common tools ---"
    for tool in make gcc ld git python3 pahole; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "[OK] $tool -> $(command -v "$tool")"
        else
            echo "[MISS] $tool"
            failed=1
        fi
    done

    if [[ "$MODE" == "gcc" || "$MODE" == "all" ]]; then
        echo "--- gcc mode tools ---"
        for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-ld; do
            if command -v "$tool" >/dev/null 2>&1; then
                echo "[OK] $tool -> $(command -v "$tool")"
            else
                echo "[MISS] $tool"
                failed=1
            fi
        done
    fi

    if [[ "$MODE" == "clang" || "$MODE" == "all" ]]; then
        echo "--- clang mode tools ---"
        for tool in clang ld.lld llvm-ar clangd bear; do
            if command -v "$tool" >/dev/null 2>&1; then
                echo "[OK] $tool -> $(command -v "$tool")"
            else
                echo "[MISS] $tool"
                failed=1
            fi
        done
    fi

    echo
    if [[ "$failed" -eq 0 ]]; then
        echo "[SUCCESS] Environment setup completed."
    else
        echo "[WARNING] Some tools are still missing. Please inspect the output above."
        exit 1
    fi
}

print_next_steps() {
    echo
    print_line
    echo " Next Steps"
    echo "--------------------------------------"
    echo "1) source \"$BASHRC_FILE\""
    echo "2) chmod +x build_kernel_arm64.sh"
    echo "3) Run build script:"
    echo "   ./build_kernel_arm64.sh"
    echo "   ./build_kernel_arm64.sh gcc"
    echo "   ./build_kernel_arm64.sh clang"
    echo "   ./build_kernel_arm64.sh gcc bear"
    echo "   ./build_kernel_arm64.sh clang kernel"
    print_line
}

main() {
    print_header
    check_mode
    require_root_or_sudo
    detect_os
    ensure_apt_based

    apt_update_once
    install_common_packages

    case "$MODE" in
        gcc)
            install_gcc_toolchain
            ;;
        clang)
            install_clang_toolchain
            ;;
        all)
            install_gcc_toolchain
            install_clang_toolchain
            ;;
    esac

    append_env_to_bashrc
    check_tools
    print_next_steps
}

main "$@"