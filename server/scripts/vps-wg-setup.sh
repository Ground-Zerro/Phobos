#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
WG_PORT="${WG_PORT:-51820}"
TUNNEL_NETWORK="${TUNNEL_NETWORK:-10.25.0.0/16}"
TUNNEL_NETWORK_V6="${TUNNEL_NETWORK_V6:-fd00:10:25::/48}"
SERVER_TUNNEL_IP="10.25.0.1"
SERVER_TUNNEL_IP_V6="fd00:10:25::1"
PHOBOS_DIR="/opt/Phobos"
WG_CONFIG_DIR="/etc/wireguard"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "==> Остановка текущего WireGuard (если запущен)..."
systemctl stop wg-quick@wg0 >/dev/null 2>&1 || true

echo "==> Установка WireGuard..."
apt update
apt install -y wireguard wireguard-tools

if [[ -z "$SERVER_PUBLIC_IP" ]]; then
  echo "==> Определение публичного IPv4 адреса..."
  SERVER_PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipecho.net/plain)
  if [[ ! "$SERVER_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_PUBLIC_IP=""
  fi
  if [[ -z "$SERVER_PUBLIC_IP" ]]; then
    echo "Не удалось автоматически определить публичный IPv4. Укажите вручную:"
    read -p "Введите публичный IPv4 адрес VPS: " SERVER_PUBLIC_IP
  fi
fi

echo "Публичный IPv4 адрес: $SERVER_PUBLIC_IP"

echo "==> Определение публичного IPv6 адреса (опционально)..."
SERVER_PUBLIC_IP_V6=""

detect_ipv6_method1() {
  if ! ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
    return 1
  fi

  if ! ping6 -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1; then
    return 1
  fi

  for service in "api64.ipify.org" "ifconfig.co" "icanhazip.com"; do
    ipv6_result=$(curl -6 -s --connect-timeout 2 --max-time 2 "https://$service" 2>/dev/null | tr -d '[:space:]')

    if [[ "$ipv6_result" =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]] || \
       [[ "$ipv6_result" =~ ^:(:([0-9a-fA-F]{1,4})){1,7}$ ]] || \
       [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ ]]; then
      echo "$ipv6_result"
      return 0
    fi
  done

  return 1
}

detect_ipv6_method2() {
  if ! ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
    return 1
  fi

  for service in "ident.me" "ipv6.icanhazip.com" "v6.ident.me"; do
    ipv6_result=$(curl -6 -s --connect-timeout 2 --max-time 2 "https://$service" 2>/dev/null | tr -d '[:space:]')

    if [[ "$ipv6_result" =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]] || \
       [[ "$ipv6_result" =~ ^:(:([0-9a-fA-F]{1,4})){1,7}$ ]] || \
       [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ ]]; then
      echo "$ipv6_result"
      return 0
    fi
  done

  return 1
}

if ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
  echo "Локальный IPv6 интерфейс обнаружен, определение публичного адреса..."

  ipv6_method1=$(timeout 8 bash -c "$(declare -f detect_ipv6_method1); detect_ipv6_method1" 2>/dev/null || echo "")

  if [[ -n "$ipv6_method1" ]] && [[ "$ipv6_method1" =~ ^[0-9a-fA-F:]+$ ]]; then
    echo "Основной метод: $ipv6_method1"

    ipv6_method2=$(timeout 8 bash -c "$(declare -f detect_ipv6_method2); detect_ipv6_method2" 2>/dev/null || echo "")

    if [[ -n "$ipv6_method2" ]] && [[ "$ipv6_method2" =~ ^[0-9a-fA-F:]+$ ]]; then
      echo "Резервный метод: $ipv6_method2"

      if [[ "$ipv6_method1" == "$ipv6_method2" ]]; then
        echo "IPv6 адрес достоверно определен: $ipv6_method1"
        SERVER_PUBLIC_IP_V6="$ipv6_method1"
      else
        echo "ВНИМАНИЕ: результаты методов различаются!"
        echo "Не удалось достоверно определить IPv6, используется $ipv6_method1"
        SERVER_PUBLIC_IP_V6="$ipv6_method1"
      fi
    else
      echo "Резервный метод не дал результата, используется: $ipv6_method1"
      SERVER_PUBLIC_IP_V6="$ipv6_method1"
    fi
  else
    echo "Основной метод не дал результата, пробуем резервный..."

    ipv6_method2=$(timeout 8 bash -c "$(declare -f detect_ipv6_method2); detect_ipv6_method2" 2>/dev/null || echo "")

    if [[ -n "$ipv6_method2" ]] && [[ "$ipv6_method2" =~ ^[0-9a-fA-F:]+$ ]]; then
      echo "IPv6 адрес определен резервным методом: $ipv6_method2"
      SERVER_PUBLIC_IP_V6="$ipv6_method2"
    else
      echo "Оба метода не смогли определить публичный IPv6"
      SERVER_PUBLIC_IP_V6=""
    fi
  fi
else
  echo "IPv6 интерфейс не обнаружен на сервере"
fi

if [[ -z "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "Публичный IPv6 недоступен (работа только через IPv4)"
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

echo "==> Определение основного сетевого интерфейса..."

# Function to detect main network interface
get_main_interface() {
  # Try to get the interface from the default route
  local iface=$(ip route | grep default | head -1 | awk '{print $5}' | head -c -1)
  if [[ -n "$iface" ]]; then
    echo "$iface"
    return 0
  fi

  # Fallback: try common interface names
  for ifname in eth0 ens3 enp1s0 wlp2s0 eno1 enp0s3; do
    if ip link show "$ifname" >/dev/null 2>&1; then
      echo "$ifname"
      return 0
    fi
  done

  # If we still can't find it, default to eth0
  echo "eth0"
}

MAIN_INTERFACE=$(get_main_interface)
echo "  Основной сетевой интерфейс: $MAIN_INTERFACE"

if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  WG_ADDRESS="$SERVER_TUNNEL_IP/16, $SERVER_TUNNEL_IP_V6/48"
  POSTUP_RULES="iptables -A FORWARD -i wg0 -o wg0 -j DROP; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE; ip6tables -A FORWARD -i wg0 -o wg0 -j DROP; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE"
  POSTDOWN_RULES="iptables -D FORWARD -i wg0 -o wg0 -j DROP; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE; ip6tables -D FORWARD -i wg0 -o wg0 -j DROP; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE"
  echo "Режим: Dual-stack (IPv4 + IPv6)"
else
  WG_ADDRESS="$SERVER_TUNNEL_IP/16"
  POSTUP_RULES="iptables -A FORWARD -i wg0 -o wg0 -j DROP; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE"
  POSTDOWN_RULES="iptables -D FORWARD -i wg0 -o wg0 -j DROP; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE"
  echo "Режим: IPv4 only"
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

echo "==> Проверка и установка MASQUERADE правил..."

# Function to check if iptables rule exists
check_iptables_rule() {
  local table=$1
  local chain=$2
  local rule=$3

  if iptables -t "$table" -C "$chain" "$rule" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Function to check if ip6tables rule exists
check_ip6tables_rule() {
  local table=$1
  local chain=$2
  local rule=$3

  if ip6tables -t "$table" -C "$chain" "$rule" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Check and add IPv4 MASQUERADE rule
if ! check_iptables_rule "nat" "POSTROUTING" "-o $MAIN_INTERFACE -j MASQUERADE"; then
  iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
  echo "  Добавлено правило IPv4 MASQUERADE"
else
  echo "  Правило IPv4 MASQUERADE уже существует"
fi

# Check and add IPv4 FORWARD rules
if ! check_iptables_rule "filter" "FORWARD" "-i wg0 -j ACCEPT"; then
  iptables -A FORWARD -i wg0 -j ACCEPT
  echo "  Добавлено правило IPv4 FORWARD для wg0"
else
  echo "  Правило IPv4 FORWARD для wg0 уже существует"
fi

if ! check_iptables_rule "filter" "FORWARD" "-i wg0 -o wg0 -j DROP"; then
  iptables -A FORWARD -i wg0 -o wg0 -j DROP
  echo "  Добавлено правило IPv4 FORWARD DROP для wg0->wg0"
else
  echo "  Правило IPv4 FORWARD DROP для wg0->wg0 уже существует"
fi

# Check and add IPv6 MASQUERADE rule if IPv6 is available
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  if ! check_ip6tables_rule "nat" "POSTROUTING" "-o $MAIN_INTERFACE -j MASQUERADE"; then
    ip6tables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
    echo "  Добавлено правило IPv6 MASQUERADE"
  else
    echo "  Правило IPv6 MASQUERADE уже существует"
  fi

  # Check and add IPv6 FORWARD rules
  if ! check_ip6tables_rule "filter" "FORWARD" "-i wg0 -j ACCEPT"; then
    ip6tables -A FORWARD -i wg0 -j ACCEPT
    echo "  Добавлено правило IPv6 FORWARD для wg0"
  else
    echo "  Правило IPv6 FORWARD для wg0 уже существует"
  fi

  if ! check_ip6tables_rule "filter" "FORWARD" "-i wg0 -o wg0 -j DROP"; then
    ip6tables -A FORWARD -i wg0 -o wg0 -j DROP
    echo "  Добавлено правило IPv6 FORWARD DROP для wg0->wg0"
  else
    echo "  Правило IPv6 FORWARD DROP для wg0->wg0 уже существует"
  fi
fi

# Attempt to save iptables rules to make them persistent across reboots
if command -v iptables-persistent >/dev/null 2>&1; then
  echo "  Сохранение правил iptables..."
  netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
  # Create iptables rules file if it doesn't exist
  if [[ ! -d /etc/iptables ]]; then
    mkdir -p /etc/iptables
  fi
  iptables-save > /etc/iptables/rules.v4
  if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
    ip6tables-save > /etc/iptables/rules.v6
  fi
  echo "  Правила iptables сохранены"
fi

echo "==> Запуск WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "==> Сохранение IP адресов..."
cat > "$PHOBOS_DIR/server/ip_addresses.env" <<EOF
SERVER_PUBLIC_IP_V4=$SERVER_PUBLIC_IP
SERVER_PUBLIC_IP_V6=$SERVER_PUBLIC_IP_V6
EOF
chmod 600 "$PHOBOS_DIR/server/ip_addresses.env"

echo "==> Настройка UFW firewall..."
if command -v ufw &>/dev/null; then
  ufw allow ${WG_PORT}/udp comment "Phobos WireGuard" 2>/dev/null || true
  ufw allow 22/tcp comment "SSH" 2>/dev/null || true
  echo "  Порт ${WG_PORT}/udp добавлен в исключения UFW"
else
  echo "  UFW не установлен, пропуск настройки"
fi

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
