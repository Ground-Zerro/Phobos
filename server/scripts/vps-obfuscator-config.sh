#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib-core.sh"

check_root

load_config() {
  if [[ -f "$SERVER_ENV" ]]; then
    source "$SERVER_ENV"
  fi
  
  OBFUSCATOR_PORT="${OBFUSCATOR_PORT:-$(grep 'source-lport' "$OBF_CONFIG" 2>/dev/null | awk '{print $3}' || echo 51821)}"
  OBFUSCATOR_KEY="${OBFUSCATOR_KEY:-$(grep 'key' "$OBF_CONFIG" 2>/dev/null | awk '{print $3}' || echo "KEY")}"
  SERVER_PUBLIC_IP_V4="${SERVER_PUBLIC_IP_V4:-0.0.0.0}"
  SERVER_PUBLIC_IP_V6="${SERVER_PUBLIC_IP_V6:-}"
  WG_LOCAL_ENDPOINT="${WG_LOCAL_ENDPOINT:-127.0.0.1:51820}"
  CLIENT_WG_PORT="${CLIENT_WG_PORT:-13255}"
  
  if [[ -f "$OBF_CONFIG" ]]; then
    CURRENT_IP=$(grep '^source-if' "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "0.0.0.0")
    CURRENT_LOG=$(grep '^verbose' "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "INFO")
    CURRENT_MASKING=$(grep '^masking' "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "AUTO")
    CURRENT_IDLE=$(grep '^idle-timeout' "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "300")
    CURRENT_DUMMY=$(grep '^max-dummy' "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "4")
  else
    CURRENT_IP="0.0.0.0"
    CURRENT_LOG="INFO"
    CURRENT_MASKING="AUTO"
    CURRENT_IDLE="300"
    CURRENT_DUMMY="4"
  fi
}

save_server_env() {
  if [[ -f "$SERVER_ENV" ]]; then
    grep -vE '^(OBFUSCATOR_PORT|OBFUSCATOR_KEY|OBFUSCATOR_DUMMY|OBFUSCATOR_IDLE|OBFUSCATOR_MASKING|SERVER_PUBLIC_IP_V4|SERVER_PUBLIC_IP_V6|WG_LOCAL_ENDPOINT|CLIENT_WG_PORT|SERVER_WG_IPV4_NETWORK|SERVER_WG_IPV6_NETWORK)=' "$SERVER_ENV" > "$SERVER_ENV.tmp"
    mv "$SERVER_ENV.tmp" "$SERVER_ENV"
  fi

  cat >> "$SERVER_ENV" <<EOF
OBFUSCATOR_PORT=$OBFUSCATOR_PORT
OBFUSCATOR_KEY=$OBFUSCATOR_KEY
OBFUSCATOR_DUMMY=$CURRENT_DUMMY
OBFUSCATOR_IDLE=$CURRENT_IDLE
OBFUSCATOR_MASKING=$CURRENT_MASKING
SERVER_PUBLIC_IP_V4=$SERVER_PUBLIC_IP_V4
SERVER_PUBLIC_IP_V6=$SERVER_PUBLIC_IP_V6
WG_LOCAL_ENDPOINT=$WG_LOCAL_ENDPOINT
CLIENT_WG_PORT=$CLIENT_WG_PORT
SERVER_WG_IPV4_NETWORK=${SERVER_WG_IPV4_NETWORK:-}
SERVER_WG_IPV6_NETWORK=${SERVER_WG_IPV6_NETWORK:-}
EOF
  chmod 600 "$SERVER_ENV"
}

apply_obfuscator_config() {
  local skip_restart="${1:-}"
  log_info "Применение настроек Obfuscator..."

  cat > "$OBF_CONFIG" <<EOF
[instance]
source-if = $CURRENT_IP
source-lport = $OBFUSCATOR_PORT
target = $WG_LOCAL_ENDPOINT
key = $OBFUSCATOR_KEY
masking = $CURRENT_MASKING
verbose = $CURRENT_LOG
idle-timeout = $CURRENT_IDLE
max-dummy = $CURRENT_DUMMY
EOF

  save_server_env

  if [[ "$skip_restart" != "skip_restart" ]]; then
    if systemctl is-active --quiet wg-obfuscator; then
      systemctl restart wg-obfuscator && log_success "Служба Obfuscator перезапущена"
    else
      systemctl start wg-obfuscator && log_success "Служба Obfuscator запущена"
    fi
    sleep 1
  else
    log_info "Конфиг создан, перезапуск пропущен"
  fi
}

change_port() {
  echo ""
  echo "Текущий порт: $OBFUSCATOR_PORT"
  read -p "Введите новый порт (или 'r' для случайного): " input
  
  if [[ "$input" == "r" ]]; then
    OBFUSCATOR_PORT=$(find_free_port) || { log_error "Нет свободных портов"; return; }
  elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
    OBFUSCATOR_PORT="$input"
  else
    log_error "Неверный порт"
    return
  fi
  
  apply_obfuscator_config
  rebuild_all_clients
  log_success "Порт сервера изменен"
  read -p "Нажмите Enter..."
}

change_client_port() {
  echo ""
  echo "Текущий внутренний порт клиента (Endpoint): $CLIENT_WG_PORT"
  read -p "Введите новый порт (1-65535): " input

  if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
    CLIENT_WG_PORT="$input"
    save_server_env
    rebuild_all_clients
    log_success "Порт клиента изменен"
  else
    log_error "Неверный порт"
  fi
  read -p "Нажмите Enter..."
}

change_interface_ip() {
  echo ""
  echo "Текущий IP интерфейса: $CURRENT_IP"
  read -p "Введите новый IP (например 0.0.0.0): " input
  if [[ -n "$input" ]]; then
    CURRENT_IP="$input"
    apply_obfuscator_config
  fi
}

change_key() {
  echo ""
  echo "Текущий ключ: $OBFUSCATOR_KEY"
  echo "1) Сгенерировать новый"
  echo "2) Ввести вручную"
  read -p "Выбор: " choice
  
  if [[ "$choice" == "1" ]]; then
    OBFUSCATOR_KEY=$(head -c 6 /dev/urandom | base64 | tr -d '+/=\n' | head -c 3)
  elif [[ "$choice" == "2" ]]; then
    read -p "Введите ключ: " input
    OBFUSCATOR_KEY="$input"
  else
    return
  fi
  
  apply_obfuscator_config
  rebuild_all_clients
  log_success "Ключ обфускации изменен"
  read -p "Нажмите Enter..."
}

rebuild_all_clients() {
  local client_script="$SCRIPT_DIR/phobos-client.sh"
  [[ ! -f "$client_script" ]] && return

  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      log_info "Пересоздание клиента $client_id..."
      "$client_script" rebuild "$client_id" >/dev/null 2>&1 || true
      "$client_script" package "$client_id" >/dev/null 2>&1 || true
    fi
  done
}

change_masking() {
  echo ""
  echo "Режим маскировки: STUN, AUTO, NONE"
  echo "Текущий: $CURRENT_MASKING"
  read -p "Новый режим: " input
  if [[ "$input" =~ ^(STUN|AUTO|NONE)$ ]]; then
    CURRENT_MASKING="$input"
    apply_obfuscator_config
    rebuild_all_clients
    log_success "Маскировка изменена"
  else
    log_error "Неверный режим"
  fi
  read -p "Нажмите Enter..."
}

change_log_level() {
  echo ""
  echo "Уровни: ERRORS, WARNINGS, INFO, DEBUG, TRACE"
  echo "Текущий: $CURRENT_LOG"
  read -p "Новый уровень: " input
  if [[ "$input" =~ ^(ERRORS|WARNINGS|INFO|DEBUG|TRACE)$ ]]; then
    CURRENT_LOG="$input"
    apply_obfuscator_config
    log_success "Уровень логов изменен"
  else
    log_error "Неверный уровень"
  fi
  read -p "Нажмите Enter..."
}

change_idle_timeout() {
  echo ""
  echo "Idle таймаут в секундах (по умолчанию: 300)"
  echo "Текущий: $CURRENT_IDLE"
  read -p "Новое значение: " input
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    CURRENT_IDLE="$input"
    apply_obfuscator_config
    rebuild_all_clients
    log_success "Таймаут изменен"
  else
    log_error "Неверное значение"
  fi
  read -p "Нажмите Enter..."
}

change_dummy() {
  echo ""
  echo "Max dummy bytes (по умолчанию: 4)"
  echo "Текущий: $CURRENT_DUMMY"
  read -p "Новое значение: " input
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    CURRENT_DUMMY="$input"
    apply_obfuscator_config
    rebuild_all_clients
    log_success "Max dummy изменен"
  else
    log_error "Неверное значение"
  fi
  read -p "Нажмите Enter..."
}

apply_template() {
  echo ""
  echo "=========================================="
  echo "    Шаблоны уровня маскировки"
  echo "=========================================="
  echo ""
  echo "  1) Легкая         (key: 3, dummy: 4)"
  echo "  2) Достаточная    (key: 6, dummy: 10)"
  echo "  3) Средняя        (key: 20, dummy: 20)"
  echo "  4) Выше среднего  (key: 50, dummy: 50)"
  echo "  5) Кошмар!        (key: 255, dummy: 100)"
  echo ""
  echo "  0) Отмена"
  echo ""

  while true; do
    read -p "Выбор [0-5]: " choice
    case "$choice" in
      0) return ;;
      1) local key_len=3; CURRENT_DUMMY=4; break ;;
      2) local key_len=6; CURRENT_DUMMY=10; break ;;
      3) local key_len=20; CURRENT_DUMMY=20; break ;;
      4) local key_len=50; CURRENT_DUMMY=50; break ;;
      5) local key_len=255; CURRENT_DUMMY=100; break ;;
      *) echo "Некорректный ввод. Введите число от 0 до 5." ;;
    esac
  done

  OBFUSCATOR_KEY=$(head -c $((key_len * 2)) /dev/urandom | base64 | tr -d '+/=\n' | head -c "$key_len")

  apply_obfuscator_config
  rebuild_all_clients
  log_success "Шаблон применен: ключ ${key_len} символов, dummy ${CURRENT_DUMMY} байт"
  read -p "Нажмите Enter..."
}

change_wg_pool() {
  echo ""
  echo "=== Смена внутреннего пула адресов WireGuard ==="
  echo "⚠ ВНИМАНИЕ: Это изменит IP сервера и ВСЕХ клиентов!"
  
  # Get current from wg0.conf
  local current_addr=$(grep "^Address" "$WG_CONFIG" | head -1 | cut -d'=' -f2- | tr -d ' ' || echo "N/A")
  echo "Текущие адреса сервера: $current_addr"
  
  read -p "Введите новую сеть IPv4 (CIDR, например 10.50.0.0/16): " new_net_v4
  if [[ ! "$new_net_v4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    log_error "Неверный формат IPv4"
    return
  fi
  
  read -p "Введите новую сеть IPv6 (CIDR, например fd00:50:0::/48) или пустую строку: " new_net_v6
  
  # Save to env
  SERVER_WG_IPV4_NETWORK="$new_net_v4"
  SERVER_WG_IPV6_NETWORK="$new_net_v6"
  save_server_env
  
  # Calculate Server IP (usually .1 in the network)
  local ip_base_v4=$(echo "$new_net_v4" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3"."}')
  local last_octet=$(echo "$new_net_v4" | cut -d'/' -f1 | awk -F. '{print $4}')
  local server_ip_v4
  if [[ "$last_octet" == "0" ]]; then
     local prefix=$(echo "$new_net_v4" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')
     server_ip_v4="${prefix}.1"
  else
     server_ip_v4=$(echo "$new_net_v4" | cut -d'/' -f1)
  fi
  local mask_v4=$(echo "$new_net_v4" | cut -d'/' -f2)
  local server_addr_str="${server_ip_v4}/${mask_v4}"

  local server_addr_full="$server_addr_str"

  if [[ -n "$new_net_v6" ]]; then
     local mask_v6=$(echo "$new_net_v6" | cut -d'/' -f2)
     local prefix_v6=$(echo "$new_net_v6" | cut -d'/' -f1 | sed 's/::.*//')
     local server_ip_v6="${prefix_v6}::1"
     server_addr_full="$server_addr_str, ${server_ip_v6}/${mask_v6}"
  fi
  
  echo "Новый адрес сервера: $server_addr_full"
  
  # Update wg0.conf
  sed -i "s|^Address = .*|Address = $server_addr_full|" "$WG_CONFIG"
  
  # Iterate clients
  echo "Обновление клиентов..."
  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      local meta="$client_dir/metadata.json"
      local conf="$client_dir/${client_id}.conf"
      
      local old_ipv4=$(jq -r '.tunnel_ip_v4 // empty' "$meta" 2>/dev/null)
      if [[ -z "$old_ipv4" ]]; then continue; fi
      
      local old_last=$(echo "$old_ipv4" | awk -F. '{print $4}')
      local old_third=$(echo "$old_ipv4" | awk -F. '{print $3}')
      
      # New IPv4
      local new_prefix_v4=$(echo "$server_ip_v4" | awk -F. '{print $1"."$2}')
      local new_client_ip_v4="${new_prefix_v4}.${old_third}.${old_last}"
      
      # New IPv6
      local new_client_ip_v6=""
      if [[ -n "$new_net_v6" ]]; then
         local hex_part=$(printf "%x:%x" "$old_third" "$old_last")
         local prefix_v6_clean=$(echo "$new_net_v6" | cut -d'/' -f1 | sed 's/::.*//')
         new_client_ip_v6="${prefix_v6_clean}::${hex_part}"
      fi
      
      log_info "Client $client_id: $old_ipv4 -> $new_client_ip_v4"
      
      # Update metadata
      if [[ -n "$new_client_ip_v6" ]]; then
        jq --arg ipv4 "$new_client_ip_v4" --arg ipv6 "$new_client_ip_v6" \
           '.tunnel_ip_v4 = $ipv4 | .tunnel_ip_v6 = $ipv6' "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
      else
         jq --arg ipv4 "$new_client_ip_v4" \
           '.tunnel_ip_v4 = $ipv4 | .tunnel_ip_v6 = null' "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
      fi
      
      # Update conf file (Address =)
      local new_conf_addr="$new_client_ip_v4/32"
      if [[ -n "$new_client_ip_v6" ]]; then
        new_conf_addr="$new_conf_addr, $new_client_ip_v6/128"
      fi
      sed -i "s|^Address = .*|Address = $new_conf_addr|" "$conf"
    fi
  done
  
  # Rebuild Peer section of wg0.conf
  log_info "Пересборка списка пиров в wg0.conf..."
  sed -n '/^\['Interface'\]/,/^$/p' "$WG_CONFIG" > "$WG_CONFIG.new"
  
  for client_dir in "$PHOBOS_DIR/clients"/*;
     do
     if [[ -d "$client_dir" ]] && [[ -f "$client_dir/metadata.json" ]]; then
        local pub=$(jq -r '.public_key' "$client_dir/metadata.json")
        local ipv4=$(jq -r '.tunnel_ip_v4' "$client_dir/metadata.json")
        local ipv6=$(jq -r '.tunnel_ip_v6 // empty' "$client_dir/metadata.json")
        
        echo "" >> "$WG_CONFIG.new"
        echo "[Peer]" >> "$WG_CONFIG.new"
        echo "PublicKey = $pub" >> "$WG_CONFIG.new"
        if [[ -n "$ipv6" ]]; then
           echo "AllowedIPs = $ipv4/32, $ipv6/128" >> "$WG_CONFIG.new"
        else
           echo "AllowedIPs = $ipv4/32" >> "$WG_CONFIG.new"
        fi
     fi
  done
  
  mv "$WG_CONFIG.new" "$WG_CONFIG"
  chmod 600 "$WG_CONFIG"

  log_info "Пересборка пакетов клиентов..."
  local client_script="$SCRIPT_DIR/phobos-client.sh"
  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      "$client_script" package "$client_id" >/dev/null 2>&1 || true
    fi
  done

  log_info "Перезапуск WireGuard..."
  systemctl restart wg-quick@wg0
  systemctl restart wg-obfuscator
  log_success "Адреса обновлены."
}

change_wg_listen_port() {
  echo ""
  echo "=== Смена порта WireGuard ==="

  local current_port=$(grep "^ListenPort" "$WG_CONFIG" | cut -d'=' -f2 | tr -d ' ')
  echo "Текущий порт WireGuard: $current_port"
  echo ""
  read -p "Введите новый порт (1024-65535) или 'r' для случайного: " input

  local new_port
  if [[ "$input" == "r" ]]; then
    new_port=$(find_free_port) || { log_error "Нет свободных портов"; read -p "Нажмите Enter..."; return; }
  elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1024 ] && [ "$input" -le 65535 ]; then
    if ss -ulnp | grep -q ":$input "; then
      log_error "Порт $input уже занят"
      read -p "Нажмите Enter..."
      return
    fi
    new_port="$input"
  else
    log_error "Неверный порт"
    read -p "Нажмите Enter..."
    return
  fi

  log_info "Смена порта WireGuard: $current_port -> $new_port"

  sed -i "s|^ListenPort = .*|ListenPort = $new_port|" "$WG_CONFIG"

  WG_LOCAL_ENDPOINT="127.0.0.1:$new_port"
  save_server_env

  apply_obfuscator_config skip_restart

  log_info "Пересборка пакетов клиентов..."
  local client_script="$SCRIPT_DIR/phobos-client.sh"
  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      "$client_script" package "$client_id" >/dev/null 2>&1 || true
    fi
  done

  log_info "Перезапуск служб..."
  systemctl restart wg-quick@wg0
  systemctl restart wg-obfuscator

  log_success "Порт WireGuard изменен на $new_port"
  read -p "Нажмите Enter..."
}

change_server_ip() {
  echo ""
  echo "Текущий публичный IP сервера: $SERVER_PUBLIC_IP_V4"
  echo "1) Определить из сетевого интерфейса"
  echo "2) Ввести вручную"
  read -p "Выбор: " choice

  local ip=""
  if [[ "$choice" == "1" ]]; then
    ip=$(get_public_ipv4) || true
    if [[ -z "$ip" ]]; then
      log_error "Не удалось определить IP из сетевого интерфейса"
      read -p "Нажмите Enter..."
      return
    fi
  elif [[ "$choice" == "2" ]]; then
    read -p "Введите IPv4: " input
    if [[ ! "$input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      log_error "Неверный формат IP"
      read -p "Нажмите Enter..."
      return
    fi
    ip="$input"
  else
    return
  fi

  SERVER_PUBLIC_IP_V4="$ip"
  save_server_env
  rebuild_all_clients
  log_success "Публичный IP сервера обновлен: $SERVER_PUBLIC_IP_V4"
  read -p "Нажмите Enter..."
}

# Menu

show_menu() {
  load_config

  clear
  echo "=========================================="
  echo "    PHOBOS - Настройка WG-Obfuscator"
  echo "=========================================="
  echo ""
  echo "  1) Шаблоны маскировки     [key: ${#OBFUSCATOR_KEY}, dummy: $CURRENT_DUMMY]"
  echo ""
  echo "  2) Порт сервера (UDP)     [$OBFUSCATOR_PORT]"
  echo "  3) Порт клиента (Local)   [$CLIENT_WG_PORT]"
  echo "  4) IP интерфейса          [$CURRENT_IP]"
  echo "  5) Ключ обфускации        [${OBFUSCATOR_KEY:0:8}...]"
  echo "  6) Маскировка             [$CURRENT_MASKING]"
  echo "  7) Уровень логов          [$CURRENT_LOG]"
  echo "  8) Idle таймаут (сек)     [$CURRENT_IDLE]"
  echo "  9) Max dummy (байт)       [$CURRENT_DUMMY]"
  echo ""
  local wg_port=$(grep "^ListenPort" "$WG_CONFIG" 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
  echo " 10) Смена пула адресов WG  (IPv4/IPv6)"
  echo " 11) Порт WireGuard         [${wg_port:-51820}]"
  echo " 12) Публичный IP сервера   [$SERVER_PUBLIC_IP_V4]"
  echo ""
  echo "  0) Назад"
  echo ""
  read -p "Выберите действие: " choice

  case $choice in
    1) apply_template ;;
    2) change_port ;;
    3) change_client_port ;;
    4) change_interface_ip ;;
    5) change_key ;;
    6) change_masking ;;
    7) change_log_level ;;
    8) change_idle_timeout ;;
    9) change_dummy ;;
    10) change_wg_pool ;;
    11) change_wg_listen_port ;;
    12) change_server_ip ;;
    0) exit 0 ;;
    *) echo "Неверный выбор" ;;
  esac
}

if [[ "${1:-}" == "apply_defaults_silent" ]]; then
  load_config
  apply_obfuscator_config skip_restart
  exit 0
fi

while true; do
  show_menu
done
