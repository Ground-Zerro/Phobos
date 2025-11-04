#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MENU_SCRIPT="$SCRIPT_DIR/phobos-menu.sh"
SYMLINK_PATH="/usr/local/bin/phobos"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "=========================================="
echo "  Установка меню Phobos"
echo "=========================================="
echo ""

if [[ ! -f "$MENU_SCRIPT" ]]; then
  echo "Ошибка: файл $MENU_SCRIPT не найден"
  exit 1
fi

echo "==> Настройка прав доступа..."
chmod +x "$MENU_SCRIPT"

echo "==> Создание симлинка..."
if [[ -L "$SYMLINK_PATH" ]]; then
  rm -f "$SYMLINK_PATH"
fi

ln -s "$MENU_SCRIPT" "$SYMLINK_PATH"

echo ""
echo "=========================================="
echo "  Установка завершена!"
echo "=========================================="
echo ""
echo "Теперь вы можете запустить меню командой: phobos"
echo ""
