#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "=========================================="
echo "  Автоматическая установка Phobos VPS"
echo "=========================================="
echo ""

echo ""
echo "==> Этап 1/7: Установка системных зависимостей"
echo ""

"$SCRIPT_DIR/vps-install-dependencies.sh"

echo ""
echo "==> Этап 2/7: Сборка wg-obfuscator из исходников"
echo ""

"$SCRIPT_DIR/vps-build-obfuscator.sh"

echo ""
echo "==> Этап 3/7: Настройка WireGuard сервера"
echo ""

"$SCRIPT_DIR/vps-wg-setup.sh"

echo ""
echo "==> Этап 4/7: Настройка wg-obfuscator сервера"
echo ""

"$SCRIPT_DIR/vps-obfuscator-setup.sh"

echo ""
echo "==> Этап 5/7: Запуск HTTP сервера для раздачи пакетов"
echo ""

"$SCRIPT_DIR/vps-start-http-server.sh"

echo ""
echo "==> Этап 6/7: Настройка автоматической очистки токенов"
echo ""

"$SCRIPT_DIR/vps-setup-token-cleanup.sh"

echo ""
echo "==> Этап 7/7: Установка интерактивного меню"
echo ""

"$SCRIPT_DIR/vps-install-menu.sh"

echo ""
echo "=========================================="
echo "  Установка Phobos VPS завершена!"
echo "=========================================="
echo ""
echo "Следующие шаги:"
echo ""
echo "   Запустите интерактивное меню:"
echo "   phobos"
echo ""
echo "   Или добавьте клиента вручную:"
echo "   $SCRIPT_DIR/vps-client-add.sh <client_name>"
echo ""
echo "Параметры сервера сохранены в: /opt/Phobos/server/server.env"
echo ""
