# Embedded Cross-Compile Doctor

嵌入式 Linux 交叉编译的一键诊断与修复工具。适用于从 Windows 开发机传输源码到 Ubuntu 进行 ARM 交叉编译的场景。

## Quick Start

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/embedded-cross-compile-doctor.git
cd embedded-cross-compile-doctor

# Diagnose (default: ARM)
./diagnose.sh --src ~/your-project

# Auto-fix common issues
./fix.sh --src ~/your-project
```

## What It Checks

| #  | Category              | Details                                              |
|----|-----------------------|------------------------------------------------------|
| 1  | Host Environment      | OS version, kernel, architecture                     |
| 2  | Cross-Compiler        | gcc/g++/strip/ar/ld presence and functionality       |
| 3  | Windows->Linux Files  | CRLF line endings, permissions, broken symlinks, paths |
| 4  | Build System          | CMake/Autotools/qmake detection and configuration    |
| 5  | Qt Cross-Compile      | Qt ARM installation, mkspec, OpenGL flags            |
| 6  | Dependencies          | make, cmake, autoconf, pkg-config, sysroot           |
| 7  | Environment Variables | CC, CROSS_COMPILE, SYSROOT, PKG_CONFIG_PATH          |
| 8  | Error Patterns        | config.log analysis, stale artifacts, missing -lpthread |

## Supported Architectures

```bash
./diagnose.sh --arch arm        # ARM 32-bit (default)
./diagnose.sh --arch armhf      # ARM hard-float
./diagnose.sh --arch aarch64    # ARM 64-bit
./diagnose.sh --arch mips       # MIPS big-endian
./diagnose.sh --arch mipsel     # MIPS little-endian
./diagnose.sh --arch riscv64    # RISC-V 64-bit
```

## Options

```
./diagnose.sh [OPTIONS]
  --src DIR          Source directory (default: current dir)
  --arch ARCH        Target architecture (default: arm)
  --toolchain PREFIX Toolchain prefix (auto-detected from --arch)
  --report FILE      Save diagnosis report to file
  --help             Show help

./fix.sh [OPTIONS]
  --src DIR          Source directory (default: current dir)
  --arch ARCH        Target architecture (default: arm)
  --toolchain PREFIX Toolchain prefix (auto-detected)
  --dry-run          Preview fixes without applying
  --help             Show help
```

## Common Scenarios

### Qt Embedded App (e.g. Car Infotainment)

```bash
# Diagnose Qt cross-compile setup
./diagnose.sh --src ~/car-app --arch arm

# Fix CRLF from Windows transfer + install toolchain
./fix.sh --src ~/car-app
sudo apt install gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
```

### CMake Project

```bash
./diagnose.sh --src ~/my-cmake-project --arch aarch64
# Will auto-generate toolchain-aarch64.cmake and build-arm.sh
./fix.sh --src ~/my-cmake-project --arch aarch64
# Then run:
cd ~/my-cmake-project && ./build-arm.sh
```

### Autotools Project (MPlayer, alsa-lib, etc.)

```bash
./diagnose.sh --src ~/MPlayer-1.4 --arch arm
# Fix will remind you to reconfigure:
./fix.sh --src ~/MPlayer-1.4
cd ~/MPlayer-1.4 && ./configure --host=arm-linux-gnueabi && make -j$(nproc)
```

## Typical Workflow

```
Windows (dev) ──scp/tar──> Ubuntu (build) ──binary──> ARM (target)
                              │
                        ./diagnose.sh    <-- you are here
                        ./fix.sh
                        make / cmake
```

1. Transfer source: `scp -r project/ user@ubuntu:~/project/`
2. Diagnose: `./diagnose.sh --src ~/project`
3. Fix: `./fix.sh --src ~/project`
4. Build: follow fix suggestions
5. Deploy: `scp binary/ user@arm-device:/opt/`

## Contributing

PRs welcome! To add a new check:

1. Add a new section in `diagnose.sh`
2. If auto-fixable, add corresponding logic in `fix.sh`
3. Update the table above in README

## License

MIT
