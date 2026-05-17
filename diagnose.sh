#!/usr/bin/env bash
# =============================================================================
# Embedded Cross-Compile Doctor - diagnose.sh
# Universal diagnostic tool for embedded Linux cross-compilation projects
# Source: Windows -> Build: Ubuntu/Debian -> Target: ARM Linux
# =============================================================================
set -uo pipefail

VERSION="1.0.0"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

REPORT_FILE=""
FIX_SUGGESTIONS=()
ERRORS=0
WARNINGS=0

# =============================================================================
# Helper functions
# =============================================================================
banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Embedded Cross-Compile Doctor${NC}  v${VERSION}                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Windows -> Ubuntu -> ARM Linux                             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

pass()    { echo -e "  ${GREEN}[PASS]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARNINGS=$((WARNINGS+1)); FIX_SUGGESTIONS+=("$2"); }
fail()    { echo -e "  ${RED}[FAIL]${NC} $1"; ERRORS=$((ERRORS+1)); FIX_SUGGESTIONS+=("$2"); }
info()    { echo -e "  ${BLUE}[INFO]${NC} $1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }

# Parse arguments
SRC_DIR="."
ARCH="arm"
TOOLCHAIN_PREFIX="arm-linux-gnueabi"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)      SRC_DIR="$2"; shift 2 ;;
        --arch)     ARCH="$2"; shift 2 ;;
        --toolchain) TOOLCHAIN_PREFIX="$2"; shift 2 ;;
        --report)   REPORT_FILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --src DIR         Source directory to scan (default: current dir)"
            echo "  --arch ARCH       Target architecture: arm, aarch64, mips, riscv (default: arm)"
            echo "  --toolchain PREFIX  Toolchain prefix, e.g. arm-linux-gnueabihf (auto-detected if omitted)"
            echo "  --report FILE     Write diagnosis report to file"
            echo "  --help            Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --src ~/my-project --arch arm"
            echo "  $0 --arch aarch64 --toolchain aarch64-linux-gnu"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Auto-detect toolchain prefix based on arch
if [[ "$TOOLCHAIN_PREFIX" == "arm-linux-gnueabi" ]]; then
    case "$ARCH" in
        arm)     TOOLCHAIN_PREFIX="arm-linux-gnueabi" ;;
        armhf)   TOOLCHAIN_PREFIX="arm-linux-gnueabihf" ;;
        aarch64) TOOLCHAIN_PREFIX="aarch64-linux-gnu" ;;
        mips)    TOOLCHAIN_PREFIX="mips-linux-gnu" ;;
        mipsel)  TOOLCHAIN_PREFIX="mipsel-linux-gnu" ;;
        riscv64) TOOLCHAIN_PREFIX="riscv64-linux-gnu" ;;
        *)       TOOLCHAIN_PREFIX="${ARCH}-linux-gnu" ;;
    esac
fi

banner
echo -e "  Source dir:       ${BOLD}${SRC_DIR}${NC}"
echo -e "  Target arch:      ${BOLD}${ARCH}${NC}"
echo -e "  Toolchain prefix: ${BOLD}${TOOLCHAIN_PREFIX}${NC}"
echo ""

# =============================================================================
# 1. Host Environment
# =============================================================================
section "1/8  Host Environment"

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    info "OS: $PRETTY_NAME"
else
    warn "Cannot detect OS version" "Install /etc/os-release or run on Ubuntu/Debian"
fi

info "Kernel: $(uname -r)"
info "Arch: $(uname -m)"

if [[ "$(uname -m)" == "x86_64" ]]; then
    pass "Running on x86_64 (good for cross-compilation)"
else
    warn "Not running on x86_64 — cross-compilation may behave differently" "Use an x86_64 host for reliable cross-compilation"
fi

# =============================================================================
# 2. Cross-Compilation Toolchain
# =============================================================================
section "2/8  Cross-Compilation Toolchain"

CC="${TOOLCHAIN_PREFIX}-gcc"
CXX="${TOOLCHAIN_PREFIX}-g++"
STRIP="${TOOLCHAIN_PREFIX}-strip"
AR="${TOOLCHAIN_PREFIX}-ar"
LD="${TOOLCHAIN_PREFIX}-ld"

for tool_bin in "$CC" "$CXX" "$STRIP" "$AR" "$LD"; do
    if command -v "$tool_bin" &>/dev/null; then
        ver=$("$tool_bin" --version 2>/dev/null | head -1 || echo "unknown")
        pass "$tool_bin found ($ver)"
    else
        fail "$tool_bin not found" "Install with: sudo apt install gcc-${TOOLCHAIN_PREFIX} g++-${TOOLCHAIN_PREFIX}"
    fi
done

# Check if the toolchain actually works
if command -v "$CC" &>/dev/null; then
    echo 'int main(){return 0;}' > /tmp/_xcompile_test.c
    if "$CC" /tmp/_xcompile_test.c -o /tmp/_xcompile_test_arm 2>/dev/null; then
        file_type=$(file /tmp/_xcompile_test_arm 2>/dev/null || echo "unknown")
        if echo "$file_type" | grep -qi "ARM\|aarch64\|MIPS\|RISC"; then
            pass "Toolchain produces ${ARCH} binaries"
        else
            fail "Toolchain output is NOT ${ARCH}: $file_type" "Wrong toolchain installed. Install: sudo apt install gcc-${TOOLCHAIN_PREFIX}"
        fi
        rm -f /tmp/_xcompile_test_arm
    else
        fail "Toolchain compilation test failed" "Toolchain may be broken. Reinstall: sudo apt install --reinstall gcc-${TOOLCHAIN_PREFIX}"
    fi
    rm -f /tmp/_xcompile_test.c
fi

# =============================================================================
# 3. Windows -> Linux File Issues
# =============================================================================
section "3/8  Windows->Linux File Issues (Line Endings & Permissions)"

# Check for CRLF line endings
crlf_count=0
if command -v grep &>/dev/null && [[ -d "$SRC_DIR" ]]; then
    crlf_count=$(find "$SRC_DIR" -maxdepth 5 -type f \( -name "*.sh" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" -o -name "Makefile" -o -name "CMakeLists.txt" -o -name "*.pro" -o -name "*.pri" -o -name "*.py" -o -name "*.conf" -o -name "*.cfg" -o -name "*.m4" -o -name "*.ac" -o -name "*.am" \) -exec grep -Pl '\r$' {} \; 2>/dev/null | wc -l)
    crlf_count=${crlf_count:-0}
fi

if [[ "$crlf_count" -gt 0 ]]; then
    fail "Found $crlf_count files with Windows CRLF line endings" "Run: find $SRC_DIR -type f \\( -name '*.sh' -o -name '*.c' -o -name '*.h' \\) -exec dos2unix {} +"
else
    pass "No CRLF line endings detected in source files"
fi

# Check for missing executable permissions on scripts
script_perm_issues=0
if [[ -d "$SRC_DIR" ]]; then
    while IFS= read -r -d '' script; do
        if [[ ! -x "$script" ]]; then
            script_perm_issues=$((script_perm_issues+1))
        fi
    done < <(find "$SRC_DIR" -maxdepth 5 -type f -name "*.sh" -print0 2>/dev/null)
fi

if [[ "$script_perm_issues" -gt 0 ]]; then
    fail "$script_perm_issues .sh files missing execute permission" "Run: find $SRC_DIR -name '*.sh' -exec chmod +x {} +"
else
    pass "All .sh files have execute permissions"
fi

# Check for broken symlinks (common when copying from Windows)
broken_links=0
if [[ -d "$SRC_DIR" ]]; then
    broken_links=$(find "$SRC_DIR" -maxdepth 5 -xtype l 2>/dev/null | wc -l)
fi

if [[ "$broken_links" -gt 0 ]]; then
    warn "Found $broken_links broken symlinks (Windows doesn't preserve symlinks)" "Re-create symlinks or re-transfer source with tar/scp"
else
    pass "No broken symlinks found"
fi

# Check for Windows-specific path characters in build files
win_path_issues=0
if [[ -d "$SRC_DIR" ]]; then
    win_path_issues=$(find "$SRC_DIR" -maxdepth 5 -type f \( -name "CMakeLists.txt" -o -name "Makefile" -o -name "*.pro" -o -name "*.cmake" -o -name "*.conf" \) -exec grep -Pl '[A-Z]:\\\\' {} + 2>/dev/null | wc -l || echo 0)
fi

if [[ "$win_path_issues" -gt 0 ]]; then
    fail "Found $win_path_issues build files with Windows-style paths (C:\\...)" "Fix paths manually or regenerate build files on Linux"
else
    pass "No Windows-style paths in build files"
fi

# =============================================================================
# 4. Build System Detection & Configuration
# =============================================================================
section "4/8  Build System Detection"

HAS_CMAKE=0; HAS_AUTOTOOLS=0; HAS_QMAKE=0; HAS_MAKEFILE=0; HAS_MESON=0

if [[ -d "$SRC_DIR" ]]; then
    [[ -f "$SRC_DIR/CMakeLists.txt" ]] && HAS_CMAKE=1 && info "Found: CMake (CMakeLists.txt)"
    [[ -f "$SRC_DIR/configure.ac" || -f "$SRC_DIR/configure.in" ]] && HAS_AUTOTOOLS=1 && info "Found: Autotools (configure.ac)"
    [[ -f "$SRC_DIR/configure" ]] && HAS_AUTOTOOLS=1 && info "Found: Autotools (configure script)"
    [[ -f "$SRC_DIR"/*.pro ]] && HAS_QMAKE=1 && info "Found: qmake (.pro file)"
    [[ -f "$SRC_DIR/Makefile" ]] && HAS_MAKEFILE=1 && info "Found: Makefile"
    [[ -f "$SRC_DIR/meson.build" ]] && HAS_MESON=1 && info "Found: Meson (meson.build)"
fi

if [[ $HAS_CMAKE -eq 0 && $HAS_AUTOTOOLS -eq 0 && $HAS_QMAKE -eq 0 && $HAS_MAKEFILE -eq 0 && $HAS_MESON -eq 0 ]]; then
    warn "No recognized build system found in $SRC_DIR" "Ensure you're pointing --src at the correct directory"
fi

# CMake toolchain file check
if [[ $HAS_CMAKE -eq 1 ]]; then
    toolchain_file=$(find "$SRC_DIR" -maxdepth 3 -name "*toolchain*.cmake" -o -name "*cross*.cmake" 2>/dev/null | head -1)
    if [[ -n "$toolchain_file" ]]; then
        pass "CMake toolchain file found: $toolchain_file"
        # Check if it references the right compiler
        if grep -q "$TOOLCHAIN_PREFIX" "$toolchain_file" 2>/dev/null; then
            pass "Toolchain file references $TOOLCHAIN_PREFIX"
        else
            warn "Toolchain file may reference a different toolchain" "Update $toolchain_file to use $TOOLCHAIN_PREFIX-gcc"
        fi
    else
        warn "No CMake toolchain file found — you need one for cross-compilation" "Create a toolchain.cmake with CMAKE_SYSTEM_NAME=Linux and set CMAKE_C_COMPILER"
    fi
fi

# Autotools cross-compile flags check
if [[ $HAS_AUTOTOOLS -eq 1 ]]; then
    if [[ -f "$SRC_DIR/config.cache" || -f "$SRC_DIR/config.status" ]]; then
        if grep -q "$(uname -m)" "$SRC_DIR/config.cache" 2>/dev/null || grep -q "$(uname -m)" "$SRC_DIR/config.status" 2>/dev/null; then
            warn "Autotools was configured for host arch, not ${ARCH}. Reconfigure needed." "Run: cd $SRC_DIR && make distclean && ./configure --host=${TOOLCHAIN_PREFIX} ..."
        fi
    fi
fi

# =============================================================================
# 5. Qt Cross-Compilation
# =============================================================================
section "5/8  Qt Cross-Compilation Setup"

QT_ARM_PREFIX="/opt/qt5-arm"
QT_FOUND=0

# Check common Qt ARM install locations
for qt_dir in "$QT_ARM_PREFIX" "/opt/qt-arm" "/usr/local/qt5-arm" "$HOME/qt5-arm"; do
    if [[ -d "$qt_dir" ]]; then
        QT_FOUND=1
        info "Qt ARM installation found at: $qt_dir"
        if [[ -f "$qt_dir/bin/qmake" ]]; then
            pass "qmake found at $qt_dir/bin/qmake"
            qt_ver=$("$qt_dir/bin/qmake" -query QT_VERSION 2>/dev/null || echo "unknown")
            info "Qt version: $qt_ver"
        else
            warn "qmake not found in $qt_dir/bin/" "Rebuild Qt with: ./configure -prefix $qt_dir -xplatform linux-arm-gnueabi-g++ ..."
        fi
        if [[ -f "$qt_dir/mkspecs/linux-arm-gnueabi-g++/qmake.conf" ]]; then
            pass "Qt mkspec for ARM found"
        else
            warn "Qt ARM mkspec not found" "Create $qt_dir/mkspecs/linux-arm-gnueabi-g++/qmake.conf"
        fi
        break
    fi
done

# Check .pro files for common issues
if [[ -d "$SRC_DIR" ]]; then
    pro_files=$(find "$SRC_DIR" -maxdepth 3 -name "*.pro" 2>/dev/null)
    if [[ -n "$pro_files" ]]; then
        while IFS= read -r pro; do
            # Check for OpenGL (problematic on embedded ARM)
            if grep -qi "opengl\|QtOpenGL" "$pro" 2>/dev/null; then
                warn "Qt project $pro uses OpenGL — may fail on headless ARM" "Remove OpenGL deps or add: QT -= opengl"
            fi
            # Check for hardcoded Windows paths
            if grep -qP '[A-Z]:\\\\' "$pro" 2>/dev/null; then
                fail "Qt project $pro contains Windows paths" "Fix paths in $pro to use Linux paths"
            fi
        done <<< "$pro_files"
    fi
fi

if [[ $QT_FOUND -eq 0 ]]; then
    info "No Qt ARM installation detected (skip if not using Qt)"
fi

# =============================================================================
# 6. Dependencies & Libraries
# =============================================================================
section "6/8  Build Dependencies"

# Check essential build tools
for pkg in make cmake autoconf automake libtool pkg-config; do
    if command -v "$pkg" &>/dev/null; then
        pass "$pkg installed"
    else
        warn "$pkg not found" "Install with: sudo apt install $pkg"
    fi
done

# Check for common cross-compilation libraries
for lib_name in zlib libssl libffi ncurses; do
    lib_pkg="${TOOLCHAIN_PREFIX}-dev"
    # These are hard to check generically, just inform
    info "If $lib_name is needed, ensure ${lib_pkg} or ARM-compiled version is available"
done

# Check if sysroot exists
sysroot_paths=("/usr/${TOOLCHAIN_PREFIX}" "/opt/${TOOLCHAIN_PREFIX}-sysroot")
for sysroot in "${sysroot_paths[@]}"; do
    if [[ -d "$sysroot" ]]; then
        pass "Sysroot found at $sysroot"
    fi
done

# =============================================================================
# 7. Environment Variables
# =============================================================================
section "7/8  Environment Variables"

# Check CC/CXX
if [[ -n "${CC:-}" ]]; then
    info "CC=$CC"
    if echo "$CC" | grep -q "$TOOLCHAIN_PREFIX"; then
        pass "CC points to correct toolchain"
    else
        warn "CC=$CC does not match expected $TOOLCHAIN_PREFIX" "export CC=${TOOLCHAIN_PREFIX}-gcc"
    fi
else
    info "CC not set (usually set in Makefile/CMake)"
fi

if [[ -n "${CROSS_COMPILE:-}" ]]; then
    info "CROSS_COMPILE=$CROSS_COMPILE"
else
    info "CROSS_COMPILE not set (set it if your build system uses it)"
fi

if [[ -n "${SYSROOT:-}" ]]; then
    info "SYSROOT=$SYSROOT"
    if [[ -d "$SYSROOT" ]]; then
        pass "SYSROOT directory exists"
    else
        fail "SYSROOT=$SYSROOT does not exist" "Fix SYSROOT path"
    fi
fi

if [[ -n "${PKG_CONFIG_PATH:-}" ]]; then
    info "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
else
    info "PKG_CONFIG_PATH not set (set if using pkg-config for ARM libs)"
fi

# =============================================================================
# 8. Common Build Error Patterns
# =============================================================================
section "8/8  Known Error Pattern Check"

if [[ -d "$SRC_DIR" ]]; then
    # Check for config.log with errors
    config_logs=$(find "$SRC_DIR" -maxdepth 3 -name "config.log" 2>/dev/null)
    if [[ -n "$config_logs" ]]; then
        while IFS= read -r log; do
            if grep -q "cannot run C compiled programs" "$log" 2>/dev/null; then
                fail "config.log shows 'cannot run C compiled programs' — classic cross-compile issue" "Add --host=${TOOLCHAIN_PREFIX} to ./configure"
            fi
            if grep -q "checking whether we are cross compiling" "$log" 2>/dev/null; then
                if grep -q "yes" "$log" 2>/dev/null; then
                    info "Autotools detected cross-compilation in $log"
                fi
            fi
        done <<< "$config_logs"
    fi

    # Check for stale build artifacts from host compilation
    if [[ -f "$SRC_DIR/Makefile" ]]; then
        if grep -q "$(uname -m)" "$SRC_DIR/Makefile" 2>/dev/null; then
            warn "Makefile may contain host-architecture artifacts" "Run make distclean and reconfigure for ${ARCH}"
        fi
    fi

    # Check for missing -lpthread / -ldl (common on ARM)
    makefiles=$(find "$SRC_DIR" -maxdepth 3 -name "Makefile" -o -name "CMakeLists.txt" 2>/dev/null)
    if [[ -n "$makefiles" ]]; then
        pthread_needed=0
        while IFS= read -r mf; do
            if grep -rq "pthread_create\|std::thread\|QThread" "$SRC_DIR" --include="*.c" --include="*.cpp" --include="*.h" 2>/dev/null; then
                if ! grep -q "lpthread\|pthread" "$mf" 2>/dev/null; then
                    pthread_needed=1
                fi
            fi
        done <<< "$makefiles"
        if [[ $pthread_needed -eq 1 ]]; then
            warn "Source uses threads but Makefile may not link -lpthread" "Add -lpthread to LDFLAGS or target_link_libraries"
        fi
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}Diagnosis Summary${NC}                                         ${CYAN}║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}All checks passed! Environment looks good.${NC}               ${CYAN}║${NC}"
else
    echo -e "${CYAN}║${NC}  ${RED}Errors: $ERRORS${NC}  ${YELLOW}Warnings: $WARNINGS${NC}                              ${CYAN}║${NC}"
fi

echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

if [[ ${#FIX_SUGGESTIONS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}${YELLOW}Fix Suggestions:${NC}"
    echo ""
    # Deduplicate suggestions
    seen_suggestions=()
    idx=1
    for suggestion in "${FIX_SUGGESTIONS[@]}"; do
        is_dup=0
        for seen in "${seen_suggestions[@]+"${seen_suggestions[@]}"}"; do
            [[ "$suggestion" == "$seen" ]] && is_dup=1 && break
        done
        if [[ $is_dup -eq 0 ]]; then
            echo -e "  ${YELLOW}${idx}.${NC} ${suggestion}"
            seen_suggestions+=("$suggestion")
            idx=$((idx+1))
        fi
    done
    echo ""
    echo -e "  ${CYAN}Tip: Run ${BOLD}./fix.sh${NC}${CYAN} to auto-fix common issues${NC}"
fi

# Write report file if requested
if [[ -n "$REPORT_FILE" ]]; then
    {
        echo "# Embedded Cross-Compile Doctor Report"
        echo "# Date: $(date)"
        echo "# Source: $SRC_DIR"
        echo "# Arch: $ARCH"
        echo "# Toolchain: $TOOLCHAIN_PREFIX"
        echo "# Errors: $ERRORS  Warnings: $WARNINGS"
        echo ""
        for suggestion in "${FIX_SUGGESTIONS[@]}"; do
            echo "- $suggestion"
        done
    } > "$REPORT_FILE"
    echo -e "\n  Report saved to: $REPORT_FILE"
fi

exit $ERRORS
