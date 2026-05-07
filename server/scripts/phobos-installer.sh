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
  (
    apt-get update -qq \
      && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireguard jq curl build-essential ufw iptables nftables
  ) >/dev/null 2>&1 &
  spin $! "Установка пакетов..."
  wait $!
  local apt_st=$?
  [[ $apt_st -eq 0 ]] || die "Установка пакетов завершилась с ошибкой (код $apt_st). Запустите: apt-get update && apt-get install -y wireguard iptables nftables"
  command -v wg >/dev/null 2>&1 || die "Команда wg не найдена после установки wireguard-tools"
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

  log_info "Сборка darkhttpd..."
  local darkhttpd_version="1.16"
  local darkhttpd_url="https://github.com/emikulic/darkhttpd/archive/refs/tags/v${darkhttpd_version}.tar.gz"
  local build_dir="/tmp/darkhttpd-build"

  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  if ! curl -sL "$darkhttpd_url" | tar -xz -C "$build_dir" --strip-components=1; then
    log_error "Не удалось скачать darkhttpd"
    exit 1
  fi

  if ! make -C "$build_dir" darkhttpd >/dev/null 2>&1; then
    log_error "Не удалось собрать darkhttpd"
    exit 1
  fi

  cp "$build_dir/darkhttpd" "$PHOBOS_DIR/bin/darkhttpd"
  chmod +x "$PHOBOS_DIR/bin/darkhttpd"
  ln -sf "$PHOBOS_DIR/bin/darkhttpd" /usr/local/bin/darkhttpd
  rm -rf "$build_dir"

  log_success "darkhttpd собран и установлен"
}

load_netfilter_wireguard_modules() {
  local mod
  for mod in wireguard iptable_nat iptable_filter ip_tables ip6_tables ip6table_filter ip6table_nat \
    nf_tables nf_nat nf_nat_ipv6 nft_nat nft_chain_nat nf_conntrack \
    xt_MASQUERADE nf_defrag_ipv4 nf_defrag_ipv6; do
    modprobe "$mod" 2>/dev/null || true
  done
}

ensure_ip6tables_nat() {
  if ip6tables -t nat -S >/dev/null 2>&1; then
    return 0
  fi
  load_netfilter_wireguard_modules
  if ip6tables -t nat -S >/dev/null 2>&1; then
    return 0
  fi
  log_info "Настройка ip6tables NAT: доустановка пакетов и повторная проверка..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables nftables >/dev/null 2>&1 || true
  load_netfilter_wireguard_modules
  ip6tables -t nat -S >/dev/null 2>&1
}

step_wg() {
  log_info "Настройка WireGuard..."
  mkdir -p /etc/wireguard

  local iface
  iface=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  [[ -z "$iface" ]] && iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
  [[ -z "$iface" || ! -d "/sys/class/net/$iface" ]] && die "Не удалось определить интерфейс для NAT (нужен default route)"

  load_netfilter_wireguard_modules

  local priv pub
  priv=$(wg genkey) || die "Не удалось сгенерировать приватный ключ WireGuard"
  pub=$(printf '%s\n' "$priv" | wg pubkey) || die "Не удалось получить публичный ключ WireGuard"

  local wg_ipv4_net="10.25.0.0/16"
  local wg_ipv6_net="fd00:10:25::/48"
  local wg_ipv4_addr="10.25.0.1/16"
  local wg_ipv6_addr="fd00:10:25::1/48"

  local ipv6_on=0
  if [[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "0" ]]; then
    ipv6_on=1
  fi

  local ipv6_nat=0
  if [[ "$ipv6_on" -eq 1 ]]; then
    if ensure_ip6tables_nat; then
      ipv6_nat=1
    else
      log_warn "Таблица ip6tables nat недоступна после установки пакетов и загрузки модулей; IPv6 NAT в PostUp не добавляется"
    fi
  fi

  local addr_line="Address = $wg_ipv4_addr"
  [[ "$ipv6_on" -eq 1 ]] && addr_line+=", $wg_ipv6_addr"

  local iface_q
  iface_q=$(printf '%q' "$iface")

  mkdir -p "$PHOBOS_DIR/server"
  cat > "$PHOBOS_DIR/server/wg0-fw.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
WAN_IFACE=${iface_q}
IPV6_ON=${ipv6_on}
IPV6_NAT=${ipv6_nat}

load_mods() {
  local m
  for m in wireguard iptable_nat iptable_filter ip_tables ip6_tables ip6table_filter ip6table_nat \\
    nf_tables nf_nat nf_nat_ipv6 nft_nat nft_chain_nat xt_MASQUERADE nf_conntrack nf_defrag_ipv4 nf_defrag_ipv6; do
    modprobe "\$m" 2>/dev/null || true
  done
}

case "\${1:-}" in
  up)
    load_mods
    iptables -C FORWARD -i wg0 -o wg0 -j DROP 2>/dev/null || iptables -A FORWARD -i wg0 -o wg0 -j DROP
    iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -t nat -C POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE
    if [[ "\$IPV6_ON" -eq 1 ]]; then
      ip6tables -C FORWARD -i wg0 -o wg0 -j DROP 2>/dev/null || ip6tables -A FORWARD -i wg0 -o wg0 -j DROP
      ip6tables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || ip6tables -A FORWARD -i wg0 -j ACCEPT
      if [[ "\$IPV6_NAT" -eq 1 ]]; then
        ip6tables -t nat -C POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE 2>/dev/null || ip6tables -t nat -A POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE
      fi
    fi
    ;;
  down)
    iptables -D FORWARD -i wg0 -o wg0 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE 2>/dev/null || true
    if [[ "\$IPV6_ON" -eq 1 ]]; then
      ip6tables -D FORWARD -i wg0 -o wg0 -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
      if [[ "\$IPV6_NAT" -eq 1 ]]; then
        ip6tables -t nat -D POSTROUTING -o "\$WAN_IFACE" -j MASQUERADE 2>/dev/null || true
      fi
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod 700 "$PHOBOS_DIR/server/wg0-fw.sh"

  cat > "$SERVER_ENV" <<EOF
SERVER_WG_PRIVATE_KEY=$priv
SERVER_WG_PUBLIC_KEY=$pub
SERVER_WG_IPV4_NETWORK=$wg_ipv4_net
SERVER_WG_IPV6_NETWORK=$wg_ipv6_net
EOF

  cat > "$WG_CONFIG" <<EOF
[Interface]
$addr_line
ListenPort = 51820
PrivateKey = $priv
PostUp = $PHOBOS_DIR/server/wg0-fw.sh up
PostDown = $PHOBOS_DIR/server/wg0-fw.sh down
EOF
  chmod 600 "$WG_CONFIG"

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-phobos.conf
  if [[ "$ipv6_on" -eq 1 ]]; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-phobos.conf
    sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
  fi
  sysctl -p /etc/sysctl.d/99-phobos.conf >/dev/null

  if ! iptables -t nat -S >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables nftables >/dev/null 2>&1 || true
    load_netfilter_wireguard_modules
  fi
  iptables -t nat -S >/dev/null 2>&1 || die "Таблица iptables nat недоступна (модуль iptable_nat или пакет iptables)"

  wg-quick down wg0 2>/dev/null || true
  ip link delete dev wg0 2>/dev/null || true

  systemctl enable wg-quick@wg0
  if ! systemctl restart wg-quick@wg0; then
    log_error "Не удалось запустить WireGuard."
    journalctl -u wg-quick@wg0 -n 50 --no-pager >&2 || true
    die "См. journalctl -xeu wg-quick@wg0.service"
  fi
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

  local port=$(find_free_port 1024 49151)
  local key=$(head -c $((key_len * 2)) /dev/urandom | base64 | tr -d '+/=\n' | head -c "$key_len")
  local pub_ip_v4
  pub_ip_v4=$(get_public_ipv4) || true
  if [[ -z "$pub_ip_v4" ]]; then
    log_warn "Не удалось определить публичный IP автоматически"
    while true; do
      read -rp "Введите публичный IPv4 сервера: " pub_ip_v4
      [[ "$pub_ip_v4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
      log_error "Неверный формат IP, повторите"
    done
  fi
  local pub_ip_v6=$(get_public_ipv6)

  cat >> "$SERVER_ENV" <<EOF
OBFUSCATOR_PORT=$port
OBFUSCATOR_KEY=$key
OBFUSCATOR_DUMMY=$dummy
OBFUSCATOR_IDLE=300
OBFUSCATOR_MASKING=STUN
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
masking = STUN
verbose = INFO
idle-timeout = 300
max-dummy = $dummy
EOF

  systemctl restart wg-obfuscator
  log_success "Obfuscator настроен на порту $port"
}

step_http() {
  log_info "Настройка HTTP сервера..."

  local port=$(find_free_port 1024 49151)

  cat > /etc/systemd/system/phobos-http.service <<EOF
[Unit]
Description=Phobos HTTP Distribution Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WWW_DIR
ExecStart=/usr/local/bin/darkhttpd $WWW_DIR --port $port --no-listing
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
