#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BUILD_DIR="${BUILD_DIR:-/tmp/wg-obfuscator-build}"
INSTALL_DIR="${INSTALL_DIR:-/opt/Phobos/bin}"
REPO_URL="https://github.com/ClusterM/wg-obfuscator.git"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "==> Установка зависимостей для сборки..."
apt update
apt install -y build-essential git make gcc g++ wget curl

echo "==> Клонирование репозитория wg-obfuscator..."
rm -rf "$BUILD_DIR"
git clone "$REPO_URL" "$BUILD_DIR"
cd "$BUILD_DIR"

echo "==> Сборка нативного бинарника для VPS..."
make clean || true
make

if [[ ! -f ./wg-obfuscator ]]; then
  echo "Ошибка: нативный бинарник не был собран"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp ./wg-obfuscator /usr/local/bin/wg-obfuscator
chmod +x /usr/local/bin/wg-obfuscator
cp ./wg-obfuscator "$INSTALL_DIR/wg-obfuscator"
chmod +x "$INSTALL_DIR/wg-obfuscator"

echo "==> Нативный бинарник установлен в /usr/local/bin/wg-obfuscator"

echo "==> Установка musl cross-compile toolchains..."

MUSL_CROSS_DIR="/opt/musl-cross"
mkdir -p "$MUSL_CROSS_DIR"

download_toolchain() {
  local arch=$1
  local url=$2
  local filename=$(basename "$url")

  if [[ ! -d "$MUSL_CROSS_DIR/$arch" ]]; then
    echo "  Загрузка toolchain для $arch..."
    cd "$MUSL_CROSS_DIR"
    wget -q "$url" -O "$filename" || curl -fsSLO "$url"
    tar xf "$filename"
    rm "$filename"
  else
    echo "  Toolchain для $arch уже установлен"
  fi
}

download_toolchain "mipsel" "https://musl.cc/mipsel-linux-muslsf-cross.tgz"
download_toolchain "mips" "https://musl.cc/mips-linux-muslsf-cross.tgz"
download_toolchain "aarch64" "https://musl.cc/aarch64-linux-musl-cross.tgz"

echo "==> Кросс-компиляция для роутеров..."

cd "$BUILD_DIR"

build_cross() {
  local arch=$1
  local toolchain_path=$2
  local target_triple=$3
  local output_name=$4

  echo "  Сборка для $arch..."
  make clean || true

  export PATH="$toolchain_path/bin:$PATH"
  export CC="${target_triple}-gcc"
  export CXX="${target_triple}-g++"
  export LD="${target_triple}-ld"
  export AR="${target_triple}-ar"
  export RANLIB="${target_triple}-ranlib"
  export CFLAGS="-static"
  export LDFLAGS="-static"

  make CC="$CC" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

  if [[ -f ./wg-obfuscator ]]; then
    cp ./wg-obfuscator "$INSTALL_DIR/$output_name"
    chmod +x "$INSTALL_DIR/$output_name"
    echo "    ✓ $output_name собран"
  else
    echo "    ✗ Ошибка сборки $output_name"
    return 1
  fi
}

build_cross "mipsel" "$MUSL_CROSS_DIR/mipsel-linux-muslsf-cross" "mipsel-linux-muslsf" "wg-obfuscator-mipsel"
build_cross "mips" "$MUSL_CROSS_DIR/mips-linux-muslsf-cross" "mips-linux-muslsf" "wg-obfuscator-mips"
build_cross "aarch64" "$MUSL_CROSS_DIR/aarch64-linux-musl-cross" "aarch64-linux-musl" "wg-obfuscator-aarch64"

echo ""
echo "==> Готово! Собранные бинарники:"
ls -lh "$INSTALL_DIR"/wg-obfuscator*

echo ""
echo "Бинарники сохранены в: $INSTALL_DIR"
echo "  - wg-obfuscator (нативный для VPS)"
echo "  - wg-obfuscator-mipsel (для роутеров MIPS Little Endian)"
echo "  - wg-obfuscator-mips (для роутеров MIPS Big Endian)"
echo "  - wg-obfuscator-aarch64 (для роутеров ARM64)"

cd /
rm -rf "$BUILD_DIR"

echo ""
echo "Временная директория сборки очищена."
