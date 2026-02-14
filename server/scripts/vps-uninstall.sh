#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_DATA="${1:-}"

source "$SCRIPT_DIR/lib-core.sh"

check_root

echo "=========================================="
echo "  Удаление Phobos VPS"
echo "=========================================="
echo ""

if [[ "$KEEP_DATA" != "--keep-data" ]]; then
  echo "ВНИМАНИЕ: Это действие удалит все компоненты Phobos:"
  echo "  - Systemd сервисы (WireGuard, obfuscator, HTTP)"
  echo "  - Все конфигурации клиентов"
  echo "  - Ключи и сертификаты"
  echo "  - Логи и данные"
  echo ""
  echo "Для сохранения клиентских данных запустите: $0 --keep-data"
  echo ""
  read -p "Вы уверены? Введите 'yes' для подтверждения: " confirmation

  if [[ "$confirmation" != "yes" ]]; then
    echo "Отмена удаления"
    exit 0
  fi
fi

echo ""
echo "==> Остановка и удаление systemd сервисов..."

if systemctl is-active --quiet wg-obfuscator 2>/dev/null; then
  systemctl stop wg-obfuscator
  echo "  ✓ wg-obfuscator остановлен"
fi

if systemctl is-enabled --quiet wg-obfuscator 2>/dev/null; then
  systemctl disable wg-obfuscator
  echo "  ✓ wg-obfuscator отключен из автозапуска"
fi

if [[ -f /etc/systemd/system/wg-obfuscator.service ]]; then
  rm /etc/systemd/system/wg-obfuscator.service
  echo "  ✓ wg-obfuscator.service удален"
fi

if systemctl is-active --quiet phobos-http 2>/dev/null; then
  systemctl stop phobos-http
  echo "  ✓ phobos-http остановлен"
fi

if systemctl is-enabled --quiet phobos-http 2>/dev/null; then
  systemctl disable phobos-http
  echo "  ✓ phobos-http отключен из автозапуска"
fi

if [[ -f /etc/systemd/system/phobos-http.service ]]; then
  rm /etc/systemd/system/phobos-http.service
  echo "  ✓ phobos-http.service удален"
fi

if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  systemctl stop wg-quick@wg0
  echo "  ✓ WireGuard остановлен"
fi

if systemctl is-enabled --quiet wg-quick@wg0 2>/dev/null; then
  systemctl disable wg-quick@wg0
  echo "  ✓ WireGuard отключен из автозапуска"
fi

systemctl daemon-reload
echo "  ✓ Systemd daemon перезагружен"

echo ""
echo "==> Удаление WireGuard конфигурации..."

if [[ -f /etc/wireguard/wg0.conf ]]; then
  rm /etc/wireguard/wg0.conf
  echo "  ✓ wg0.conf удален"
fi

if [[ -f /etc/sysctl.d/99-phobos.conf ]]; then
  rm /etc/sysctl.d/99-phobos.conf
  sysctl -p 2>/dev/null || true
  echo "  ✓ 99-phobos.conf удален"
fi

echo ""
echo "==> Удаление cron задач..."

if [[ -f /etc/cron.d/phobos-cleanup ]]; then
  rm /etc/cron.d/phobos-cleanup
  echo "  ✓ /etc/cron.d/phobos-cleanup удален"
else
  echo "  - Cron задачи не найдены"
fi

echo ""
echo "==> Удаление бинарных файлов..."

if [[ -f /usr/local/bin/wg-obfuscator ]]; then
  rm /usr/local/bin/wg-obfuscator
  echo "  ✓ wg-obfuscator удален"
fi

if [[ -L /usr/local/bin/phobos ]]; then
  rm /usr/local/bin/phobos
  echo "  ✓ phobos (симлинк) удален"
fi

if [[ "$KEEP_DATA" == "--keep-data" ]]; then
  echo ""
  echo "==> Сохранение клиентских данных..."

  BACKUP_DIR="/root/phobos-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  if [[ -d "$PHOBOS_DIR/clients" ]]; then
    cp -r "$PHOBOS_DIR/clients" "$BACKUP_DIR/"
    echo "  ✓ Клиенты сохранены в $BACKUP_DIR/clients"
  fi

  if [[ -d "$PHOBOS_DIR/packages" ]]; then
    cp -r "$PHOBOS_DIR/packages" "$BACKUP_DIR/"
    echo "  ✓ Пакеты сохранены в $BACKUP_DIR/packages"
  fi

  if [[ -f "$PHOBOS_DIR/server/server.env" ]]; then
    cp "$PHOBOS_DIR/server/server.env" "$BACKUP_DIR/"
    echo "  ✓ Конфигурация (включая ключи) сохранена в $BACKUP_DIR/server.env"
  fi

  echo ""
  echo "  Резервная копия создана: $BACKUP_DIR"
fi

echo ""
echo "==> Удаление директорий..."

if [[ -d "$PHOBOS_DIR" ]]; then
  rm -rf "$PHOBOS_DIR"
  echo "  ✓ $PHOBOS_DIR удален"
fi

echo ""
echo "=========================================="
echo "  Phobos успешно удален!"
echo "=========================================="
echo ""

if [[ "$KEEP_DATA" == "--keep-data" ]]; then
  echo "Резервная копия данных: $BACKUP_DIR"
  echo ""
fi

echo "Для полной очистки системы также удалите:"
echo "  - WireGuard: apt remove --purge wireguard wireguard-tools"
echo "  - Зависимости: apt autoremove"
echo ""
