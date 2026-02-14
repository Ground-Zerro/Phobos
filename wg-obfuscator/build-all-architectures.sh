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

download_file() {
    local url=$1
    local dest=$2
    if command -v curl >/dev/null 2>&1; then
        curl -sL --max-time 60 --retry 3 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=60 --tries=3 -O "$dest" "$url"
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi
}

download_file_with_fallback() {
    local path=$1
    local dest=$2
    local -a MIRRORS=(
        "http://archive.ubuntu.com/ubuntu/pool"
        "http://ru.archive.ubuntu.com/ubuntu/pool"
    )
    for mirror in "${MIRRORS[@]}"; do
        if download_file "${mirror}/${path}" "$dest" && [ -s "$dest" ]; then
            return 0
        fi
    done
    return 1
}

noble_repo_add() {
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main universe" \
        | sudo tee /etc/apt/sources.list.d/noble-mips-cross.list >/dev/null
    printf 'Package: *\nPin: release n=noble\nPin-Priority: 100\n' \
        | sudo tee /etc/apt/preferences.d/noble-mips-cross >/dev/null
    sudo apt-get update -qq
}

noble_repo_remove() {
    sudo rm -f /etc/apt/sources.list.d/noble-mips-cross.list
    sudo rm -f /etc/apt/preferences.d/noble-mips-cross
    sudo apt-get update -qq
}

install_mips_from_noble() {
    log_info "Adding Ubuntu 24.04 (noble) repo for MIPS cross-compiler dependencies..."
    noble_repo_add

    local tmpdir
    tmpdir=$(mktemp -d)

    local -a PKGS=(
        "universe/g/gcc-12-cross/gcc-12-cross-base_12.3.0-17ubuntu1cross1_all.deb"
        "universe/g/gcc-12-cross-mipsen/gcc-12-cross-base-mipsen_12.3.0-17ubuntu1cross3_all.deb"
        "universe/b/binutils-mipsen/binutils-mips-linux-gnu_2.42-2ubuntu1cross5_amd64.deb"
        "universe/b/binutils-mipsen/binutils-mipsel-linux-gnu_2.42-2ubuntu1cross5_amd64.deb"
        "universe/g/gcc-12-cross-mipsen/cpp-12-mips-linux-gnu_12.3.0-17ubuntu1cross3_amd64.deb"
        "universe/g/gcc-12-cross-mipsen/cpp-12-mipsel-linux-gnu_12.3.0-17ubuntu1cross3_amd64.deb"
        "universe/g/gcc-12-cross-mipsen/gcc-12-mips-linux-gnu_12.3.0-17ubuntu1cross3_amd64.deb"
        "universe/g/gcc-12-cross-mipsen/gcc-12-mipsel-linux-gnu_12.3.0-17ubuntu1cross3_amd64.deb"
        "universe/c/cross-toolchain-base-mipsen/linux-libc-dev-mips-cross_6.8.0-25.25cross2_all.deb"
        "universe/c/cross-toolchain-base-mipsen/linux-libc-dev-mipsel-cross_6.8.0-25.25cross2_all.deb"
        "universe/c/cross-toolchain-base-mipsen/libc6-mips-cross_2.39-0ubuntu8cross2_all.deb"
        "universe/c/cross-toolchain-base-mipsen/libc6-dev-mips-cross_2.39-0ubuntu8cross2_all.deb"
        "universe/c/cross-toolchain-base-mipsen/libc6-mipsel-cross_2.39-0ubuntu8cross2_all.deb"
        "universe/c/cross-toolchain-base-mipsen/libc6-dev-mipsel-cross_2.39-0ubuntu8cross2_all.deb"
        "universe/g/gcc-12-cross-mipsen/libgcc-12-dev-mips-cross_12.3.0-17ubuntu1cross3_all.deb"
        "universe/g/gcc-12-cross-mipsen/libgcc-12-dev-mipsel-cross_12.3.0-17ubuntu1cross3_all.deb"
    )

    local failed=0
    for pkg_path in "${PKGS[@]}"; do
        local pkg_name
        pkg_name=$(basename "$pkg_path")
        log_info "Downloading ${pkg_name}..."
        if ! download_file_with_fallback "${pkg_path}" "${tmpdir}/${pkg_name}"; then
            log_error "Failed to download ${pkg_name}"
            failed=1
            break
        fi
    done

    if [ $failed -eq 0 ]; then
        log_info "Installing MIPS packages (noble repo active for dependency resolution)..."
        if sudo apt-get install -y --allow-downgrades "${tmpdir}"/*.deb; then
            for pair in "mips-linux-gnu" "mipsel-linux-gnu"; do
                if [ ! -f "/usr/bin/${pair}-gcc" ] && [ -f "/usr/bin/${pair}-gcc-12" ]; then
                    sudo ln -sf "/usr/bin/${pair}-gcc-12" "/usr/bin/${pair}-gcc"
                    log_info "Created symlink: /usr/bin/${pair}-gcc -> /usr/bin/${pair}-gcc-12"
                fi
            done
            rm -rf "$tmpdir"
            noble_repo_remove
            return 0
        fi
        log_error "apt install failed with noble repo"
        failed=1
    fi

    rm -rf "$tmpdir"
    noble_repo_remove
    return 1
}

install_mips_from_bootlin() {
    log_info "Trying Bootlin pre-built toolchains for MIPS..."
    local BOOTLIN_BASE="https://toolchains.bootlin.com/downloads/releases/toolchains"
    local INSTALL_DIR="/opt/cross"
    local tmpdir
    tmpdir=$(mktemp -d)

    mkdir -p "$INSTALL_DIR"

    local -a ARCH_LIST=(
        "mips32|mips32--uclibc--stable-2024.02-1|mips-buildroot-linux-uclibc|mips-linux-gnu"
        "mips32el|mips32el--uclibc--stable-2024.02-1|mipsel-buildroot-linux-uclibc|mipsel-linux-gnu"
    )

    for entry in "${ARCH_LIST[@]}"; do
        local arch_dir compiler_prefix tarball_base link_prefix
        arch_dir=$(echo "$entry" | cut -d'|' -f1)
        tarball_base=$(echo "$entry" | cut -d'|' -f2)
        compiler_prefix=$(echo "$entry" | cut -d'|' -f3)
        link_prefix=$(echo "$entry" | cut -d'|' -f4)
        local tarball="${tarball_base}.tar.bz2"

        log_info "Downloading Bootlin ${arch_dir} toolchain (~200 MB)..."
        if ! download_file "${BOOTLIN_BASE}/${arch_dir}/tarballs/${tarball}" "${tmpdir}/${tarball}"; then
            log_error "Failed to download Bootlin ${arch_dir} toolchain"
            rm -rf "$tmpdir"
            return 1
        fi

        log_info "Extracting ${arch_dir} toolchain..."
        tar -xjf "${tmpdir}/${tarball}" -C "$INSTALL_DIR"
        rm -f "${tmpdir}/${tarball}"

        local toolchain_dir
        toolchain_dir=$(ls -d "${INSTALL_DIR}/${tarball_base}" 2>/dev/null | head -1)
        if [ -z "$toolchain_dir" ]; then
            log_error "Extracted toolchain directory not found"
            rm -rf "$tmpdir"
            return 1
        fi

        for tool in gcc g++ ar ld strip nm objdump objcopy as ranlib; do
            local real_bin="${toolchain_dir}/bin/${compiler_prefix}-${tool}"
            [ -f "$real_bin" ] || continue
            printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_bin" \
                | sudo tee "/usr/local/bin/${link_prefix}-${tool}" >/dev/null
            sudo chmod +x "/usr/local/bin/${link_prefix}-${tool}"
        done

        log_success "Bootlin ${arch_dir} toolchain installed to ${toolchain_dir}"
    done

    rm -rf "$tmpdir"
    return 0
}

install_cross_compilers() {
    log_info "Installing cross-compilers and dependencies..."

    if [ -f /etc/debian_version ]; then
        log_info "Detected Debian/Ubuntu system"
        sudo apt-get update

        local mips_ok=0
        if sudo apt-get install -y \
            gcc \
            gcc-mips-linux-gnu \
            gcc-mipsel-linux-gnu \
            gcc-aarch64-linux-gnu \
            gcc-arm-linux-gnueabihf \
            binutils-mips-linux-gnu \
            binutils-mipsel-linux-gnu \
            binutils-aarch64-linux-gnu \
            binutils-arm-linux-gnueabihf \
            libc6-dev \
            libc6-dev-mips-cross \
            libc6-dev-mipsel-cross \
            libc6-dev-arm64-cross \
            libc6-dev-armhf-cross 2>/dev/null; then
            mips_ok=1
        fi

        if [ $mips_ok -eq 0 ]; then
            log_warn "MIPS packages not found in current repos, trying Ubuntu 24.04 (noble) archives..."
            if ! install_mips_from_noble; then
                log_warn "Noble archive method failed, trying Bootlin pre-built toolchains..."
                if ! install_mips_from_bootlin; then
                    log_error "Failed to install MIPS cross-compilers from all sources"
                    log_error "Manual option: https://toolchains.bootlin.com/"
                fi
            fi

            sudo apt-get install -y \
                gcc \
                gcc-aarch64-linux-gnu \
                gcc-arm-linux-gnueabihf \
                binutils-aarch64-linux-gnu \
                binutils-arm-linux-gnueabihf \
                libc6-dev \
                libc6-dev-arm64-cross \
                libc6-dev-armhf-cross 2>/dev/null || true
        fi

        log_success "Cross-compilers installation complete"

    elif [ -f /etc/redhat-release ]; then
        log_info "Detected RedHat/CentOS/Fedora system"
        sudo yum install -y gcc gcc-mips64-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnu glibc-static || \
        sudo dnf install -y gcc gcc-mips64-linux-gnu gcc-aarch64-linux-gnu gcc-arm-linux-gnu glibc-static
        log_success "Cross-compilers and dependencies installed"

    elif [ -f /etc/arch-release ]; then
        log_info "Detected Arch Linux system"
        sudo pacman -S --needed gcc mips-linux-gnu-gcc aarch64-linux-gnu-gcc arm-linux-gnueabihf-gcc
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
    local has_i686=false
    local has_arm=false

    check_compiler "gcc" && has_gcc=true
    check_compiler "mips-linux-gnu-gcc" && has_mips=true
    check_compiler "mipsel-linux-gnu-gcc" && has_mipsel=true
    check_compiler "aarch64-linux-gnu-gcc" && has_aarch64=true
    check_compiler "arm-linux-gnueabihf-gcc" && has_arm=true

    echo

    if ! $has_gcc || ! $has_mips || ! $has_mipsel || ! $has_aarch64 || ! $has_arm; then
        log_warn "Some cross-compilers are missing, installing automatically..."
        install_cross_compilers
        check_compiler "gcc" && has_gcc=true
        check_compiler "mips-linux-gnu-gcc" && has_mips=true
        check_compiler "mipsel-linux-gnu-gcc" && has_mipsel=true
        check_compiler "aarch64-linux-gnu-gcc" && has_aarch64=true
        check_compiler "arm-linux-gnueabihf-gcc" && has_arm=true
        echo
    fi

    local build_count=0
    local success_count=0

    if $has_gcc || check_compiler "gcc"; then
        log_info "=== Building for x86_64 ==="
        if build_for_arch "x86_64" "gcc" "" "wg-obfuscator-x86_64" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_mips || check_compiler "mips-linux-gnu-gcc"; then
        log_info "=== Building for MIPS ==="
        if build_for_arch "mips" "mips-linux-gnu-gcc" "" "wg-obfuscator-mips" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_mipsel || check_compiler "mipsel-linux-gnu-gcc"; then
        log_info "=== Building for MIPSEL ==="
        if build_for_arch "mipsel" "mipsel-linux-gnu-gcc" "" "wg-obfuscator-mipsel" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_aarch64 || check_compiler "aarch64-linux-gnu-gcc"; then
        log_info "=== Building for AARCH64 ==="
        if build_for_arch "aarch64" "aarch64-linux-gnu-gcc" "" "wg-obfuscator-aarch64" "static"; then
            success_count=$((success_count + 1))
        fi
        build_count=$((build_count + 1))
        echo
    fi

    if $has_arm || check_compiler "arm-linux-gnueabihf-gcc"; then
        log_info "=== Building for ARMv7 ==="
        if build_for_arch "armv7" "arm-linux-gnueabihf-gcc" "" "wg-obfuscator-armv7" "static"; then
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
