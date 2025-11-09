#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "=========================================="
echo "  Установка системных зависимостей"
echo "=========================================="
echo ""

echo "==> Обновление списка пакетов"
apt-get update

echo "==> Установка основных зависимостей"
apt-get install -y \
  wget \
  curl \
  jq \
  python3 \
  openssl \
  wireguard \
  wireguard-tools \
  iptables \
  cron

echo ""
echo "=========================================="
echo "  Зависимости успешно установлены!"
echo "=========================================="
echo ""
echo "Установленные пакеты:"
echo "  - wget, curl (загрузка файлов, определение IP)"
echo "  - jq (обработка JSON)"
echo "  - python3 (HTTP сервер)"
echo "  - openssl (генерация ключей)"
echo "  - wireguard, wireguard-tools (VPN)"
echo "  - iptables (firewall)"
echo "  - cron (планировщик задач)"
echo ""
