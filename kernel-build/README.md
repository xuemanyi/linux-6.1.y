
# ARM64 Linux Kernel Build Toolkit

一套用于 ARM64 Linux 内核编译的脚本工具，支持：

- GCC / Clang 编译
- Bear 或 Kernel 原生方式生成 `compile_commands.json`
- 交互式选择编译模式
- 输出目录隔离（gcc / clang）
- 构建日志记录

---

## 项目结构

```text
kernel-build/
├── setup_kernel_build_env.sh
├── build_kernel_arm64.sh
└── README.md
````

---

## 快速开始

### 1. 安装环境

```bash
chmod +x setup_kernel_build_env.sh build_kernel_arm64.sh
./setup_kernel_build_env.sh
source ~/.bashrc
```

---

### 2. 进入内核源码目录

```bash
cd /path/to/linux-kernel
```

---

### 3. 编译

#### 交互模式（推荐）

```bash
/path/to/kernel-build/build_kernel_arm64.sh
```

#### 命令行模式

```bash
# gcc
./build_kernel_arm64.sh gcc

# clang
./build_kernel_arm64.sh clang

# gcc + bear
./build_kernel_arm64.sh gcc bear

# clang + kernel compile_commands
./build_kernel_arm64.sh clang kernel
```

---

## 参数说明

```bash
./build_kernel_arm64.sh [COMPILER] [CCDB] [TARGETS...]
```

### COMPILER

* `gcc`
* `clang`

### CCDB（compile_commands.json）

* `none`（默认）
* `bear`
* `kernel`

### TARGETS（默认）

```text
Image modules dtbs vmlinux
```

---

## 常用示例

```bash
# GCC 默认构建
./build_kernel_arm64.sh gcc

# Clang 构建 + compile_commands.json
./build_kernel_arm64.sh clang kernel

# Bear 捕获编译命令
./build_kernel_arm64.sh gcc bear

# 自定义目标
./build_kernel_arm64.sh clang kernel Image modules

# menuconfig
./build_kernel_arm64.sh gcc none menuconfig
```

---

## 输出目录

```text
output-gcc/
output-clang/
```

---

## 关键产物

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

### Kernel 原生

```bash
./build_kernel_arm64.sh clang kernel
```

（优先 `make compile_commands.json`，失败则回退内核脚本）

---

## 注意

* 必须在内核源码根目录运行
* 默认会执行：

```bash
make mrproper
```

（会清理 `.config`）

---