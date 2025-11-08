#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
BIN_DIR="${SCRIPT_DIR}/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_compiler() {
    local compiler=$1
    if command -v "$compiler" >/dev/null 2>&1; then
        log_success "Compiler found: $compiler ($(${compiler} --version | head -1))"
        return 0
    else
        log_warn "Compiler not found: $compiler"
        return 1
    fi
}

install_cross_compilers() {
    log_info "Installing cross-compilers and dependencies..."

    if [ -f /etc/debian_version ]; then
        log_info "Detected Debian/Ubuntu system"
        sudo apt-get update
        sudo apt-get install -y \
            gcc \
            gcc-mips-linux-gnu \
            gcc-mipsel-linux-gnu \
            gcc-aarch64-linux-gnu \
            binutils-mips-linux-gnu \
            binutils-mipsel-linux-gnu \
            binutils-aarch64-linux-gnu \
            libc6-dev-mips-cross \
            libc6-dev-mipsel-cross \
            libc6-dev-arm64-cross
        log_success "Cross-compilers and dependencies installed"
    elif [ -f /etc/redhat-release ]; then
        log_info "Detected RedHat/CentOS/Fedora system"
        sudo yum install -y gcc gcc-mips64-linux-gnu gcc-aarch64-linux-gnu glibc-static || \
        sudo dnf install -y gcc gcc-mips64-linux-gnu gcc-aarch64-linux-gnu glibc-static
        log_success "Cross-compilers and dependencies installed"
    elif [ -f /etc/arch-release ]; then
        log_info "Detected Arch Linux system"
        sudo pacman -S --needed gcc mips-linux-gnu-gcc aarch64-linux-gnu-gcc
        log_success "Cross-compilers and dependencies installed"
    else
        log_error "Unsupported distribution. Please install cross-compilers manually."
        exit 1
    fi
}

build_for_arch() {
    local arch=$1
    local cc=$2
    local cflags=$3
    local output_name=$4
    local use_static=$5

    log_info "Building for ${arch}..."

    local build_arch_dir="${BUILD_DIR}/${arch}"
    mkdir -p "${build_arch_dir}"

    cd "${SCRIPT_DIR}"
    make clean >/dev/null 2>&1 || true

    local make_cmd="CC=\"${cc}\" EXTRA_CFLAGS=\"${cflags}\""
    if [ "$use_static" = "static" ]; then
        make_cmd="$make_cmd STATIC=1"
    fi

    if eval $make_cmd make -j$(nproc) 2>&1 | tee "${build_arch_dir}/build.log"; then
        if [ -f "${SCRIPT_DIR}/wg-obfuscator" ]; then
            mkdir -p "${BIN_DIR}"
            cp "${SCRIPT_DIR}/wg-obfuscator" "${BIN_DIR}/${output_name}"

            local size=$(ls -lh "${BIN_DIR}/${output_name}" | awk '{print $5}')
            local file_info=$(file "${BIN_DIR}/${output_name}" | cut -d: -f2)

            log_success "Build completed: ${output_name} (${size})"
            echo "           ${file_info}"

            echo "${arch}|SUCCESS|${size}|${file_info}" >> "${BUILD_DIR}/build_report.txt"
            return 0
        else
            log_error "Binary not found after build"
            echo "${arch}|FAILED|N/A|Binary not created" >> "${BUILD_DIR}/build_report.txt"
            return 1
        fi
    else
        log_error "Build failed for ${arch}"
        echo "${arch}|FAILED|N/A|Compilation error" >> "${BUILD_DIR}/build_report.txt"
        return 1
    fi
}

show_summary() {
    echo
    echo "========================================"
    echo "    BUILD SUMMARY"
    echo "========================================"
    echo

    if [ -f "${BUILD_DIR}/build_report.txt" ]; then
        printf "%-12s | %-10s | %-8s | %s\n" "ARCH" "STATUS" "SIZE" "DETAILS"
        echo "------------------------------------------------------------------------"

        while IFS='|' read -r arch status size details; do
            if [ "$status" = "SUCCESS" ]; then
                printf "${GREEN}%-12s${NC} | ${GREEN}%-10s${NC} | %-8s | %s\n" "$arch" "$status" "$size" "$details"
            else
                printf "${RED}%-12s${NC} | ${RED}%-10s${NC} | %-8s | %s\n" "$arch" "$status" "$size" "$details"
            fi
        done < "${BUILD_DIR}/build_report.txt"

        echo

        local success_count=$(grep -c "SUCCESS" "${BUILD_DIR}/build_report.txt" || echo 0)
        local total_count=$(wc -l < "${BUILD_DIR}/build_report.txt")

        echo "Results: ${success_count}/${total_count} successful builds"
        echo

        if [ -d "${BIN_DIR}" ] && [ "$(ls -A ${BIN_DIR} 2>/dev/null)" ]; then
            echo "Built binaries located in: ${BIN_DIR}"
            echo
            ls -lh "${BIN_DIR}"
        fi
    fi

    echo
    echo "Build logs: ${BUILD_DIR}/"
    echo "========================================"
}

main() {
    echo
    echo "========================================"
    echo "  WireGuard Obfuscator Multi-Arch Build"
    echo "========================================"
    echo

    log_info "Build directory: ${BUILD_DIR}"
    log_info "Binary output directory: ${BIN_DIR}"
    echo

    mkdir -p "${BUILD_DIR}"
    mkdir -p "${BIN_DIR}"
    rm -f "${BUILD_DIR}/build_report.txt"

    log_info "Checking available compilers..."
    echo

    local has_gcc=false
    local has_mips=false
    local has_mipsel=false
    local has_aarch64=false

    check_compiler "gcc" && has_gcc=true
    check_compiler "mips-linux-gnu-gcc" && has_mips=true
    check_compiler "mipsel-linux-gnu-gcc" && has_mipsel=true
    check_compiler "aarch64-linux-gnu-gcc" && has_aarch64=true

    echo

    if ! $has_gcc || ! $has_mips || ! $has_mipsel || ! $has_aarch64; then
        log_warn "Some cross-compilers are missing"
        read -p "Do you want to install missing compilers? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_cross_compilers
            check_compiler "gcc" && has_gcc=true
            check_compiler "mips-linux-gnu-gcc" && has_mips=true
            check_compiler "mipsel-linux-gnu-gcc" && has_mipsel=true
            check_compiler "aarch64-linux-gnu-gcc" && has_aarch64=true
        else
            log_warn "Proceeding with available compilers only"
        fi
        echo
    fi

    local build_count=0
    local success_count=0

    if $has_gcc || check_compiler "gcc"; then
        log_info "=== Building for x86_64 ==="
        if build_for_arch "x86_64" "gcc" "" "wg-obfuscator" ""; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_mips || check_compiler "mips-linux-gnu-gcc"; then
        log_info "=== Building for MIPS ==="
        local mips_flags="-march=mips32r2 -mtune=24kc -fno-strict-aliasing -fweb -frename-registers"
        if build_for_arch "mips" "mips-linux-gnu-gcc" "${mips_flags}" "wg-obfuscator-mips" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_mipsel || check_compiler "mipsel-linux-gnu-gcc"; then
        log_info "=== Building for MIPSEL ==="
        local mipsel_flags="-march=mips32r2 -mtune=24kc -EL -fno-strict-aliasing -fweb -frename-registers"
        if build_for_arch "mipsel" "mipsel-linux-gnu-gcc" "${mipsel_flags}" "wg-obfuscator-mipsel" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_aarch64 || check_compiler "aarch64-linux-gnu-gcc"; then
        log_info "=== Building for AARCH64 ==="
        local aarch64_flags="-march=armv8-a+crc -mtune=cortex-a53 -fomit-frame-pointer -fweb"
        if build_for_arch "aarch64" "aarch64-linux-gnu-gcc" "${aarch64_flags}" "wg-obfuscator-aarch64" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    make clean >/dev/null 2>&1 || true

    show_summary

    if [ $success_count -eq $build_count ]; then
        log_success "All builds completed successfully!"
        exit 0
    else
        log_warn "Some builds failed. Check logs in ${BUILD_DIR}/"
        exit 1
    fi
}

main "$@"
