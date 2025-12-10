#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

INSTALL_DIR="${INSTALL_DIR:-/opt/Phobos/bin}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_SOURCE_DIR="$REPO_ROOT/wg-obfuscator/bin"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if [[ ! -d "$BIN_SOURCE_DIR" ]]; then
  echo "Ошибка: папка с бинарниками не найдена: $BIN_SOURCE_DIR"
  exit 1
fi

echo "==> Создание директории для бинарников..."
mkdir -p "$INSTALL_DIR"

echo "==> Копирование бинарников wg-obfuscator..."

if [[ -f "$BIN_SOURCE_DIR/wg-obfuscator-x86_64" ]]; then
  cp "$BIN_SOURCE_DIR/wg-obfuscator-x86_64" "$INSTALL_DIR/wg-obfuscator"
  chmod +x "$INSTALL_DIR/wg-obfuscator"
  if [[ -f /usr/local/bin/wg-obfuscator ]]; then
    rm /usr/local/bin/wg-obfuscator
  fi
  cp "$INSTALL_DIR/wg-obfuscator" /usr/local/bin/wg-obfuscator

  cp "$BIN_SOURCE_DIR/wg-obfuscator-x86_64" "$INSTALL_DIR/wg-obfuscator-x86_64"
  chmod +x "$INSTALL_DIR/wg-obfuscator-x86_64"

  echo "  ✓ wg-obfuscator (x86_64) скопирован"
  echo "  ✓ wg-obfuscator-x86_64 (для пакетов) скопирован"
else
  echo "  ✗ Ошибка: wg-obfuscator-x86_64 не найден"
  exit 1
fi

for arch_file in "$BIN_SOURCE_DIR"/wg-obfuscator-*; do
  if [[ -f "$arch_file" ]]; then
    filename=$(basename "$arch_file")
    cp "$arch_file" "$INSTALL_DIR/$filename"
    chmod +x "$INSTALL_DIR/$filename"
    echo "  ✓ $filename скопирован"
  fi
done

echo ""
echo "==> Готово! Установленные бинарники:"
ls -lh "$INSTALL_DIR"/wg-obfuscator*
ls -lh /usr/local/bin/wg-obfuscator

echo ""
echo "Бинарники установлены в:"
echo "  - $INSTALL_DIR (все архитектуры)"
echo "  - /usr/local/bin/wg-obfuscator (для VPS)"
