#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ "$SCRIPT_DIR" != "/opt/Phobos/repo/server/scripts" ]]; then
  echo "[INFO] Копирование файлов репозитория в /opt/Phobos/repo..."
  mkdir -p /opt/Phobos/repo
  cp -r "$REPO_ROOT"/* /opt/Phobos/repo/
  rm -rf /opt/Phobos/repo/.git 2>/dev/null || true

  if [[ -x "/opt/Phobos/repo/server/scripts/phobos-installer.sh" ]]; then
    echo "[INFO] Перезапуск установщика из /opt/Phobos/repo..."
    exec /opt/Phobos/repo/server/scripts/phobos-installer.sh "$@"
  fi
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib-core.sh"

check_root

OBF_LEVEL="${OBF_LEVEL:-2}"

get_obf_params() {
  local level="${1:-2}"
  case "$level" in
    1) echo "3 4" ;;
    2) echo "6 10" ;;
    3) echo "20 20" ;;
    4) echo "50 50" ;;
    5) echo "255 100" ;;
    *) echo "6 10" ;;
  esac
}

log_info "Остановка существующих служб Phobos..."
systemctl stop wg-obfuscator 2>/dev/null || true
systemctl stop phobos-http 2>/dev/null || true
systemctl stop wg-quick@wg0 2>/dev/null || true

spin() {
  local pid=$1
  local msg=$2
  local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  while kill -0 "$pid" 2>/dev/null; do
    for (( i=0; i<${#chars}; i++ )); do
      printf "\r[%s] %s" "${chars:$i:1}" "$msg"
      sleep 0.1
    done
  done
  printf "\r"
}

step_deps() {
  log_info "Установка зависимостей..."
  (apt-get update -qq && apt-get install -y -qq wireguard qrencode jq curl build-essential git cmake python3 ufw) >/dev/null 2>&1 &
  spin $! "Установка пакетов..."
  wait $!
  log_success "Зависимости установлены."
}

step_build() {
  log_info "Копирование бинарников wg-obfuscator..."

  if [[ -d "$REPO_DIR/wg-obfuscator/bin" ]]; then
    cp -f "$REPO_DIR/wg-obfuscator/bin"/wg-obfuscator-* "$PHOBOS_DIR/bin/" 2>/dev/null || true
  fi

  local arch=$(uname -m)
  if [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-$arch" ]]; then
    log_error "Бинарник wg-obfuscator для $arch не найден!"
    exit 1
  fi

  chmod +x "$PHOBOS_DIR/bin/wg-obfuscator-$arch"
  ln -sf "$PHOBOS_DIR/bin/wg-obfuscator-$arch" /usr/local/bin/wg-obfuscator
  chmod +x /usr/local/bin/wg-obfuscator
  log_success "Бинарник wg-obfuscator установлен"
}

step_wg() {
  log_info "Настройка WireGuard..."
  mkdir -p /etc/wireguard

  local priv=$(wg genkey)
  local pub=$(echo "$priv" | wg pubkey)
  local wg_ipv4_net="10.25.0.0/16"
  local wg_ipv6_net="fd00:10:25::/48"
  local wg_ipv4_addr="10.25.0.1/16"
  local wg_ipv6_addr="fd00:10:25::1/48"

  cat > "$SERVER_ENV" <<EOF
SERVER_WG_PRIVATE_KEY=$priv
SERVER_WG_PUBLIC_KEY=$pub
SERVER_WG_IPV4_NETWORK=$wg_ipv4_net
SERVER_WG_IPV6_NETWORK=$wg_ipv6_net
EOF

  local iface=$(ip route | grep default | awk '{print $5}' | head -1)

  cat > "$WG_CONFIG" <<EOF
[Interface]
Address = $wg_ipv4_addr, $wg_ipv6_addr
ListenPort = 51820
PrivateKey = $priv
PostUp = iptables -A FORWARD -i wg0 -o wg0 -j DROP; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $iface -j MASQUERADE; ip6tables -A FORWARD -i wg0 -o wg0 -j DROP; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o wg0 -j DROP; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $iface -j MASQUERADE; ip6tables -D FORWARD -i wg0 -o wg0 -j DROP; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o $iface -j MASQUERADE
EOF
  chmod 600 "$WG_CONFIG"

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-phobos.conf
  sysctl -p /etc/sysctl.d/99-phobos.conf >/dev/null

  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0
  log_success "WireGuard настроен"
}

get_public_ipv6() {
  local iface=$(ip route | grep default | awk '{print $5}' | head -1)
  [[ -z "$iface" ]] && return

  local ipv6=$(ip -6 addr show dev "$iface" scope global 2>/dev/null | grep -oP 'inet6 \K[0-9a-f:]+' | grep -v '^f[cd]' | head -1)
  [[ -n "$ipv6" ]] && echo "$ipv6"
}

step_obf() {
  log_info "Настройка Obfuscator..."

  local params=$(get_obf_params "$OBF_LEVEL")
  local key_len=$(echo "$params" | cut -d' ' -f1)
  local dummy=$(echo "$params" | cut -d' ' -f2)

  local port=$((100 + RANDOM % 600))
  local key=$(head -c $((key_len * 2)) /dev/urandom | base64 | tr -d '+/=\n' | head -c "$key_len")
  local pub_ip_v4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "")
  local pub_ip_v6=$(get_public_ipv6)

  cat >> "$SERVER_ENV" <<EOF
OBFUSCATOR_PORT=$port
OBFUSCATOR_KEY=$key
OBFUSCATOR_DUMMY=$dummy
OBFUSCATOR_IDLE=300
SERVER_PUBLIC_IP_V4=$pub_ip_v4
SERVER_PUBLIC_IP_V6=$pub_ip_v6
WG_LOCAL_ENDPOINT=127.0.0.1:51820
CLIENT_WG_PORT=13255
EOF

  cat > /etc/systemd/system/wg-obfuscator.service <<EOF
[Unit]
Description=WireGuard Traffic Obfuscator
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wg-obfuscator --config /opt/Phobos/server/wg-obfuscator.conf
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable wg-obfuscator

  cat > "$OBF_CONFIG" <<EOF
[instance]
source-if = 0.0.0.0
source-lport = $port
target = 127.0.0.1:51820
key = $key
masking = AUTO
verbose = INFO
idle-timeout = 300
max-dummy = $dummy
EOF

  systemctl restart wg-obfuscator
  log_success "Obfuscator настроен на порту $port"
}

step_http() {
  log_info "Настройка HTTP сервера..."

  local port=80
  if ss -tlnp | grep -q ":80 "; then
    port=8080
  fi

  cat > /etc/systemd/system/phobos-http.service <<EOF
[Unit]
Description=Phobos HTTP Distribution Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WWW_DIR
ExecStart=/usr/bin/python3 $REPO_DIR/server/scripts/phobos-http-server.py $port $WWW_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable phobos-http
  systemctl restart phobos-http

  echo "HTTP_PORT=$port" >> "$SERVER_ENV"

  log_success "HTTP сервер настроен на порту $port"
}

step_final() {
  log_info "Настройка Cron..."
  echo "*/10 * * * * root $REPO_DIR/server/scripts/phobos-system.sh cleanup" > /etc/cron.d/phobos-cleanup
  chmod 644 /etc/cron.d/phobos-cleanup

  log_info "Установка меню..."
  ln -sf "$REPO_DIR/server/scripts/phobos-menu.sh" /usr/local/bin/phobos

  log_success "Установка завершена! Запустите 'phobos' для управления системой."
}

ensure_dirs
step_deps
step_build
step_wg
step_obf
step_http
step_final
