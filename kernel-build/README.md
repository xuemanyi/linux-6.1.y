# ARM64 Linux Kernel Build Toolkit

A simple toolkit for building ARM64 Linux kernels with:

- GCC / Clang support
- `compile_commands.json` via Bear or kernel-native method
- Interactive build mode
- Isolated output directories (gcc / clang)
- Build log generation

---

## Project Structure

```text
kernel-build/
├── setup_kernel_build_env.sh
├── build_kernel_arm64.sh
└── README.md
````

---

## Quick Start

### 1. Setup Environment

```bash
chmod +x setup_kernel_build_env.sh build_kernel_arm64.sh
./setup_kernel_build_env.sh
source ~/.bashrc
```

---

### 2. Enter Kernel Source Directory

```bash
cd /path/to/linux-kernel
```

---

### 3. Build Kernel

#### Interactive Mode (Recommended)

```bash
/path/to/kernel-build/build_kernel_arm64.sh
```

#### Command Line Mode

```bash
# gcc
./kernel-build/build_kernel_arm64.sh gcc

# clang
./kernel-build/build_kernel_arm64.sh clang

# gcc + bear
./kernel-build/build_kernel_arm64.sh gcc bear

# clang + kernel compile_commands
./kernel-build/build_kernel_arm64.sh clang kernel
```

---

## Usage

```bash
./build_kernel_arm64.sh [COMPILER] [CCDB] [TARGETS...]
```

### COMPILER

* `gcc`
* `clang`

### CCDB (compile_commands.json)

* `none` (default)
* `bear`
* `kernel`

### TARGETS (default)

```text
Image modules dtbs vmlinux
```

---

## Common Examples

```bash
# GCC build
./build_kernel_arm64.sh gcc

# Clang + compile_commands.json
./build_kernel_arm64.sh clang kernel

# Bear mode
./build_kernel_arm64.sh gcc bear

# Custom targets
./build_kernel_arm64.sh clang kernel Image modules

# menuconfig
./build_kernel_arm64.sh gcc none menuconfig
```

---

## Output Directories

```text
output-gcc/
output-clang/
```

---

## Build Artifacts

```text
Image:      output-*/arch/arm64/boot/Image
DTB:        output-*/arch/arm64/boot/dts/
Modules:    output-*/lib/modules/
vmlinux:    output-*/vmlinux
config:     output-*/.config
ccdb:       output-*/compile_commands.json
```

---

## compile_commands.json

### Bear

```bash
./build_kernel_arm64.sh clang bear
```

### Kernel Native

```bash
./build_kernel_arm64.sh clang kernel
```

This will:

1. Try:

```bash
make compile_commands.json
```

2. Fallback to:

```bash
python3 scripts/clang-tools/gen_compile_commands.py
```

---

## Notes

* Must run inside Linux kernel source root
* Script will run:

```bash
make mrproper
```

(This cleans `.config` and build artifacts)

---

## Troubleshooting

### Missing gcc

```bash
sudo apt install gcc-aarch64-linux-gnu
```

### Missing clang

```bash
sudo apt install clang lld
```

### Missing bear

```bash
sudo apt install bear
```

### menuconfig error

```bash
sudo apt install libncurses-dev
```

---

## Example Workflow

```bash
./setup_kernel_build_env.sh
source ~/.bashrc

cd linux/
../build_kernel_arm64.sh clang kernel
```

---

## TODO

* Incremental build mode
* ccache support
* Auto symlink for compile_commands.json
* Android / GKI support

```

---