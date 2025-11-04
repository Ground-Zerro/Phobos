#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
WG_PORT="${WG_PORT:-51820}"
TUNNEL_NETWORK="${TUNNEL_NETWORK:-10.8.0.0/24}"
TUNNEL_NETWORK_V6="${TUNNEL_NETWORK_V6:-fd00:10:8::/64}"
SERVER_TUNNEL_IP="10.8.0.1"
SERVER_TUNNEL_IP_V6="fd00:10:8::1"
PHOBOS_DIR="/opt/Phobos"
WG_CONFIG_DIR="/etc/wireguard"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "==> Установка WireGuard..."
apt update
apt install -y wireguard wireguard-tools

if [[ -z "$SERVER_PUBLIC_IP" ]]; then
  echo "==> Определение публичного IPv4 адреса..."
  SERVER_PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipecho.net/plain)
  if [[ -z "$SERVER_PUBLIC_IP" ]]; then
    echo "Не удалось автоматически определить публичный IPv4. Укажите вручную:"
    read -p "Введите публичный IPv4 адрес VPS: " SERVER_PUBLIC_IP
  fi
fi

echo "Публичный IPv4 адрес: $SERVER_PUBLIC_IP"

echo "==> Определение публичного IPv6 адреса (опционально)..."
SERVER_PUBLIC_IP_V6=$(curl -6 -s --max-time 3 ifconfig.me 2>/dev/null || curl -6 -s --max-time 3 icanhazip.com 2>/dev/null || echo "")
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "Публичный IPv6 адрес: $SERVER_PUBLIC_IP_V6"
else
  echo "IPv6 адрес не обнаружен (не критично)"
fi

mkdir -p "$PHOBOS_DIR/server"
mkdir -p "$WG_CONFIG_DIR"

echo "==> Генерация ключей WireGuard сервера..."
umask 077
wg genkey > "$PHOBOS_DIR/server/server_private.key"
wg pubkey < "$PHOBOS_DIR/server/server_private.key" > "$PHOBOS_DIR/server/server_public.key"

SERVER_PRIVATE_KEY=$(cat "$PHOBOS_DIR/server/server_private.key")
SERVER_PUBLIC_KEY=$(cat "$PHOBOS_DIR/server/server_public.key")

echo "==> Создание конфигурации WireGuard сервера..."

if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  WG_ADDRESS="$SERVER_TUNNEL_IP/24, $SERVER_TUNNEL_IP_V6/64"
  POSTUP_RULES="iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
  POSTDOWN_RULES="iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
  echo "Dual-stack режим: IPv4 + IPv6"
else
  WG_ADDRESS="$SERVER_TUNNEL_IP/24"
  POSTUP_RULES="iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
  POSTDOWN_RULES="iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
  echo "IPv4 режим"
fi

cat > "$WG_CONFIG_DIR/wg0.conf" <<EOF
[Interface]
Address = $WG_ADDRESS
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
SaveConfig = false

PostUp = $POSTUP_RULES
PostDown = $POSTDOWN_RULES
EOF

chmod 600 "$WG_CONFIG_DIR/wg0.conf"

echo "==> Включение IP forwarding..."
cat > /etc/sysctl.d/99-wireguard.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo "==> Запуск WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "==> Настройка firewall..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  echo "Порт 22/tcp (SSH) открыт в ufw"
  ufw allow $WG_PORT/udp || true
  echo "Порт $WG_PORT/udp открыт в ufw"
else
  echo "ufw не установлен. Убедитесь, что порты 22/tcp и $WG_PORT/udp открыты в firewall."
fi

echo "==> Сохранение IP адресов..."
cat > "$PHOBOS_DIR/server/ip_addresses.env" <<EOF
SERVER_PUBLIC_IP_V4=$SERVER_PUBLIC_IP
SERVER_PUBLIC_IP_V6=$SERVER_PUBLIC_IP_V6
EOF
chmod 600 "$PHOBOS_DIR/server/ip_addresses.env"

echo ""
echo "==> WireGuard сервер успешно установлен и запущен!"
echo ""
echo "Параметры сервера:"
echo "  Публичный IPv4: $SERVER_PUBLIC_IP"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "  Публичный IPv6: $SERVER_PUBLIC_IP_V6"
fi
echo "  WireGuard порт (локальный): $WG_PORT"
echo "  Туннельная сеть IPv4: $TUNNEL_NETWORK"
echo "  Туннельный IP сервера (IPv4): $SERVER_TUNNEL_IP"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "  Туннельная сеть IPv6: $TUNNEL_NETWORK_V6"
  echo "  Туннельный IP сервера (IPv6): $SERVER_TUNNEL_IP_V6"
fi
echo ""
echo "Ключи сохранены в:"
echo "  Приватный ключ: $PHOBOS_DIR/server/server_private.key"
echo "  Публичный ключ: $PHOBOS_DIR/server/server_public.key"
echo ""
echo "Публичный ключ сервера (для клиентов):"
echo "  $SERVER_PUBLIC_KEY"
echo ""
echo "Статус WireGuard:"
wg show
