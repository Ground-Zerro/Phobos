#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLIENT_NAME="${1:-}"
CLIENT_IP="${CLIENT_IP:-}"
PHOBOS_DIR="/opt/Phobos"
WG_CONFIG="/etc/wireguard/wg0.conf"
SERVER_ENV="$PHOBOS_DIR/server/server.env"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0 <client_name>"
  exit 1
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "Использование: $0 <client_name>"
  echo ""
  echo "Пример: $0 home-router"
  exit 1
fi

if [[ ! -f "$SERVER_ENV" ]]; then
  echo "Ошибка: файл $SERVER_ENV не найден."
  echo "Сначала запустите vps-obfuscator-setup.sh"
  exit 1
fi

source "$SERVER_ENV"

TOKEN_TTL="${TOKEN_TTL:-3600}"

if [[ ! -f "$PHOBOS_DIR/server/server_public.key" ]]; then
  echo "Ошибка: публичный ключ сервера не найден."
  echo "Сначала запустите vps-wg-setup.sh"
  exit 1
fi

SERVER_PUBLIC_KEY=$(cat "$PHOBOS_DIR/server/server_public.key")

CLIENT_ID=$(echo "$CLIENT_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
CLIENT_DIR="$PHOBOS_DIR/clients/$CLIENT_ID"

if [[ -d "$CLIENT_DIR" ]]; then
  echo "Ошибка: клиент $CLIENT_ID уже существует."
  exit 1
fi

if [[ -z "$CLIENT_IP" ]]; then
  echo "==> Автоматическое назначение IP адреса клиенту..."

  declare -A used_ips_map

  for existing_client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$existing_client_dir" ]] && [[ -f "$existing_client_dir/metadata.json" ]]; then
      existing_ipv4=$(jq -r '.tunnel_ip_v4 // empty' "$existing_client_dir/metadata.json" 2>/dev/null)
      if [[ -n "$existing_ipv4" ]]; then
        used_ips_map["$existing_ipv4"]=1
      fi
    fi
  done

  USED_FROM_WG=$(grep -oP 'AllowedIPs\s*=\s*10\.25\.\K\d+\.\d+/32' "$WG_CONFIG" 2>/dev/null | sed 's|/32||' || true)
  while IFS= read -r ip; do
    if [[ -n "$ip" ]]; then
      used_ips_map["10.25.$ip"]=1
    fi
  done <<< "$USED_FROM_WG"

  found_free_ip=false
  for third_octet in $(seq 0 255); do
    for fourth_octet in $(seq 2 254); do
      candidate_ip="10.25.$third_octet.$fourth_octet"

      if [[ -z "${used_ips_map[$candidate_ip]:-}" ]]; then
        CLIENT_IP="$candidate_ip"
        found_free_ip=true
        echo "Найден свободный IP: $CLIENT_IP"
        break 2
      fi
    done
  done

  if [[ "$found_free_ip" == false ]]; then
    echo "Ошибка: закончились IP адреса в подсети 10.25.0.0/16"
    exit 1
  fi
fi

mkdir -p "$CLIENT_DIR"

CLIENT_IP_V4="$CLIENT_IP"

THIRD_OCTET=$(echo "$CLIENT_IP" | cut -d. -f3)
FOURTH_OCTET=$(echo "$CLIENT_IP" | cut -d. -f4)
IPV6_HEX=$(printf "%x:%x" "$THIRD_OCTET" "$FOURTH_OCTET")
CLIENT_IP_V6="fd00:10:25::$IPV6_HEX"

echo "IP адрес клиента (IPv4): $CLIENT_IP_V4/32"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "IP адрес клиента (IPv6): $CLIENT_IP_V6/128"
fi

echo "==> Генерация ключей клиента..."
umask 077
wg genkey > "$CLIENT_DIR/client_private.key"
wg pubkey < "$CLIENT_DIR/client_private.key" > "$CLIENT_DIR/client_public.key"

CLIENT_PRIVATE_KEY=$(cat "$CLIENT_DIR/client_private.key")
CLIENT_PUBLIC_KEY=$(cat "$CLIENT_DIR/client_public.key")

echo "==> Создание конфигурации WireGuard для клиента..."

if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  WG_CLIENT_ADDRESS="$CLIENT_IP_V4/32, $CLIENT_IP_V6/128"
  WG_CLIENT_ALLOWED_IPS="0.0.0.0/0, ::/0"
else
  WG_CLIENT_ADDRESS="$CLIENT_IP_V4/32"
  WG_CLIENT_ALLOWED_IPS="0.0.0.0/0"
fi

cat > "$CLIENT_DIR/${CLIENT_ID}.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $WG_CLIENT_ADDRESS
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = 127.0.0.1:13255
AllowedIPs = $WG_CLIENT_ALLOWED_IPS
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_DIR/${CLIENT_ID}.conf"

echo "==> Создание конфигурации wg-obfuscator для клиента (только IPv4)..."

CURRENT_MAX_DUMMY=$(grep "^max-dummy" "$PHOBOS_DIR/server/wg-obfuscator.conf" | cut -d'=' -f2- | tr -d ' ' 2>/dev/null || echo "4")

cat > "$CLIENT_DIR/wg-obfuscator.conf" <<EOF
[instance]
source-if = 127.0.0.1
source-lport = 13255
target = $SERVER_PUBLIC_IP_V4:$OBFUSCATOR_PORT
key = $OBFUSCATOR_KEY
masking = AUTO
verbose = INFO
idle-timeout = 86400
max-dummy = $CURRENT_MAX_DUMMY
EOF

chmod 600 "$CLIENT_DIR/wg-obfuscator.conf"

echo "==> Создание метаданных клиента..."

cat > "$CLIENT_DIR/metadata.json" <<EOF
{
  "client_id": "$CLIENT_ID",
  "client_name": "$CLIENT_NAME",
  "tunnel_ip_v4": "$CLIENT_IP_V4",
  "tunnel_ip_v6": "$CLIENT_IP_V6",
  "public_key": "$CLIENT_PUBLIC_KEY",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "obfuscator_key": "$OBFUSCATOR_KEY",
  "server_ip_v4": "$SERVER_PUBLIC_IP_V4",
  "server_ip_v6": "$SERVER_PUBLIC_IP_V6",
  "server_port": "$OBFUSCATOR_PORT"
}
EOF

chmod 600 "$CLIENT_DIR/metadata.json"

echo "==> Добавление peer в конфигурацию WireGuard сервера..."

if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  PEER_ALLOWED_IPS="$CLIENT_IP_V4/32, $CLIENT_IP_V6/128"
else
  PEER_ALLOWED_IPS="$CLIENT_IP_V4/32"
fi

awk '
  BEGIN { in_peer = 0; empty_lines = 0 }
  /^\[Peer\]$/ {
    if (in_peer && peer_block != "") {
      print "[Peer]"
      print peer_block
      print ""
    }
    in_peer = 1
    peer_block = ""
    empty_lines = 0
    next
  }
  /^$/ {
    empty_lines++
    if (!in_peer && empty_lines <= 1) {
      print
    }
    next
  }
  /^#/ {
    next
  }
  in_peer {
    empty_lines = 0
    if (peer_block != "") peer_block = peer_block "\n"
    peer_block = peer_block $0
    next
  }
  {
    empty_lines = 0
    print
  }
  END {
    if (in_peer && peer_block != "") {
      print "[Peer]"
      print peer_block
      print ""
    }
  }
' "$WG_CONFIG" > "$WG_CONFIG.tmp" && mv "$WG_CONFIG.tmp" "$WG_CONFIG"

cat >> "$WG_CONFIG" <<EOF
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $PEER_ALLOWED_IPS
EOF

echo "==> Применение конфигурации WireGuard..."
wg syncconf wg0 <(wg-quick strip wg0)

echo ""
echo "==> Клиент $CLIENT_NAME успешно создан!"
echo ""
echo "Параметры клиента:"
echo "  ID: $CLIENT_ID"
echo "  Туннельный IP (IPv4): $CLIENT_IP_V4/32"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "  Туннельный IP (IPv6): $CLIENT_IP_V6/128"
fi
echo "  Публичный ключ: $CLIENT_PUBLIC_KEY"
echo "  Сервер (obfuscator): $SERVER_PUBLIC_IP_V4:$OBFUSCATOR_PORT"
echo ""
echo "Файлы клиента сохранены в: $CLIENT_DIR"
echo "  - client_private.key"
echo "  - client_public.key"
echo "  - ${CLIENT_ID}.conf (WireGuard dual-stack)"
echo "  - wg-obfuscator.conf (obfuscator IPv4 only)"
echo "  - metadata.json"
echo ""
echo "Статус WireGuard:"
wg show wg0
echo ""
echo "==> Автоматическая генерация установочного пакета..."
echo ""

"$SCRIPT_DIR/vps-generate-package.sh" "$CLIENT_ID"

echo ""
echo "==> Автоматическая генерация команды установки..."
echo ""

"$SCRIPT_DIR/vps-generate-install-command.sh" "$CLIENT_ID" "${TOKEN_TTL:-86400}"
