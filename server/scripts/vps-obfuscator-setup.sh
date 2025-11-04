#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

OBFUSCATOR_LISTEN_PORT="${OBFUSCATOR_LISTEN_PORT:-}"
OBFUSCATOR_KEY="${OBFUSCATOR_KEY:-}"
WG_LOCAL_ENDPOINT="${WG_LOCAL_ENDPOINT:-127.0.0.1:51820}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
PHOBOS_DIR="/opt/Phobos"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if [[ ! -f /usr/local/bin/wg-obfuscator ]]; then
  echo "Ошибка: wg-obfuscator не установлен."
  echo "Сначала запустите vps-build-obfuscator.sh"
  exit 1
fi

mkdir -p "$PHOBOS_DIR/server"

if [[ -f "$PHOBOS_DIR/server/ip_addresses.env" ]]; then
  echo "==> Загрузка IP адресов из ip_addresses.env..."
  source "$PHOBOS_DIR/server/ip_addresses.env"
  SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP_V4}"
  SERVER_PUBLIC_IP_V6="${SERVER_PUBLIC_IP_V6}"
fi

if [[ -z "$SERVER_PUBLIC_IP" ]]; then
  echo "==> Определение публичного IPv4 адреса..."
  SERVER_PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipecho.net/plain)
  if [[ -z "$SERVER_PUBLIC_IP" ]]; then
    echo "Не удалось автоматически определить публичный IPv4. Укажите вручную:"
    read -p "Введите публичный IPv4 адрес VPS: " SERVER_PUBLIC_IP
  fi
fi

if [[ -z "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "==> Определение публичного IPv6 адреса (опционально)..."
  SERVER_PUBLIC_IP_V6=$(curl -6 -s --max-time 3 ifconfig.me 2>/dev/null || curl -6 -s --max-time 3 icanhazip.com 2>/dev/null || echo "")
fi

echo "Публичный IPv4 адрес: $SERVER_PUBLIC_IP"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "Публичный IPv6 адрес: $SERVER_PUBLIC_IP_V6"
fi

if [[ -z "$OBFUSCATOR_LISTEN_PORT" ]]; then
  echo "==> Генерация случайного UDP порта для obfuscator..."
  OBFUSCATOR_LISTEN_PORT=$(shuf -i 10000-60000 -n 1)

  while ss -ulpn 2>/dev/null | grep -q ":$OBFUSCATOR_LISTEN_PORT "; do
    echo "  Порт $OBFUSCATOR_LISTEN_PORT занят, генерируем новый..."
    OBFUSCATOR_LISTEN_PORT=$(shuf -i 10000-60000 -n 1)
  done
fi

echo "Порт obfuscator: $OBFUSCATOR_LISTEN_PORT/udp"

if [[ -z "$OBFUSCATOR_KEY" ]]; then
  echo "==> Генерация симметричного ключа обфускации..."
  OBFUSCATOR_KEY=$(head -c 3 /dev/urandom | base64 | tr -d '+/=' | head -c 3)
fi

echo "==> Сохранение параметров сервера..."

cat > "$PHOBOS_DIR/server/server.env" <<EOF
OBFUSCATOR_PORT=$OBFUSCATOR_LISTEN_PORT
OBFUSCATOR_KEY=$OBFUSCATOR_KEY
SERVER_PUBLIC_IP_V4=$SERVER_PUBLIC_IP
SERVER_PUBLIC_IP_V6=$SERVER_PUBLIC_IP_V6
SERVER_PUBLIC_IP=$SERVER_PUBLIC_IP
WG_LOCAL_ENDPOINT=$WG_LOCAL_ENDPOINT
EOF

chmod 600 "$PHOBOS_DIR/server/server.env"

echo "==> Создание конфигурации wg-obfuscator..."

cat > "$PHOBOS_DIR/server/wg-obfuscator.conf" <<EOF
[instance]
source-if = 0.0.0.0
source-lport = $OBFUSCATOR_LISTEN_PORT
target = $WG_LOCAL_ENDPOINT
key = $OBFUSCATOR_KEY
masking = AUTO
verbose = INFO
idle-timeout = 86400
max-dummy = 4
EOF

chmod 600 "$PHOBOS_DIR/server/wg-obfuscator.conf"

echo "==> Создание systemd service..."

cat > /etc/systemd/system/wg-obfuscator.service <<EOF
[Unit]
Description=WireGuard Traffic Obfuscator
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wg-obfuscator --config $PHOBOS_DIR/server/wg-obfuscator.conf
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wg-obfuscator

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "==> Настройка firewall..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  echo "Порт 22/tcp (SSH) открыт в ufw"
  ufw allow $OBFUSCATOR_LISTEN_PORT/udp || true
  echo "Порт $OBFUSCATOR_LISTEN_PORT/udp открыт в ufw"
else
  echo "ufw не установлен. Убедитесь, что порты 22/tcp и $OBFUSCATOR_LISTEN_PORT/udp открыты в firewall."
fi

echo "==> Запуск wg-obfuscator..."
systemctl enable wg-obfuscator
systemctl start wg-obfuscator

sleep 2

echo ""
echo "==> wg-obfuscator успешно установлен и запущен!"
echo ""
echo "Параметры obfuscator:"
echo "  Публичный порт: $OBFUSCATOR_LISTEN_PORT/udp"
echo "  Ключ обфускации: $OBFUSCATOR_KEY"
echo "  Переадресация на: $WG_LOCAL_ENDPOINT"
echo ""
echo "Файлы конфигурации:"
echo "  Параметры сервера: $PHOBOS_DIR/server/server.env"
echo "  Конфиг obfuscator: $PHOBOS_DIR/server/wg-obfuscator.conf"
echo ""
echo "Статус службы:"
systemctl status wg-obfuscator --no-pager -l
echo ""
echo "Проверка прослушиваемого порта:"
ss -ulpn | grep ":$OBFUSCATOR_LISTEN_PORT" || echo "Порт не прослушивается (проверьте логи)"
