#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib-core.sh"

check_root
load_env
ensure_dirs

CMD="${1:-help}"
CLIENT_ARG="${2:-}"
EXTRA_ARG="${3:-}"

resolve_client() {
  local name="$1"
  local id=$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  
  if [[ -d "$CLIENTS_DIR/$id" ]]; then
    echo "$id"
    return 0
  fi
  return 1
}

action_add() {
  local name="$CLIENT_ARG"
  local manual_ip="$EXTRA_ARG"
  
  if [[ -z "$name" ]]; then die "Использование: $0 add <client_name> [ip]"; fi
  
  local id=$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
  local dir="$CLIENTS_DIR/$id"
  
  if [[ -d "$dir" ]]; then die "Клиент $id уже существует."; fi

  if [[ -z "$SERVER_WG_PUBLIC_KEY" ]]; then
    die "Публичный ключ сервера не найден в server.env. Запустите установку."
  fi

  local server_pub="$SERVER_WG_PUBLIC_KEY"
  local server_ip_v4="${SERVER_PUBLIC_IP_V4:-}"
  local server_ip_v6="${SERVER_PUBLIC_IP_V6:-}"
  
  # --- IP Allocation ---
  local client_ip_v4="$manual_ip"
  local ipv4_prefix_main=$(echo "${SERVER_WG_IPV4_NETWORK:-10.25.0.0/16}" | cut -d'/' -f1 | cut -d'.' -f1-2)
  local ipv6_prefix_main=$(echo "${SERVER_WG_IPV6_NETWORK:-fd00:10:25::/48}" | cut -d'/' -f1 | sed 's/::.*//')
  
  if [[ -z "$client_ip_v4" ]]; then
    log_info "Поиск свободного IP..."
    declare -A used_ips
    
    # Scan files
    for d in "$CLIENTS_DIR"/*; do
      if [[ -d "$d" ]] && [[ -f "$d/metadata.json" ]]; then
        local ip=$(jq -r '.tunnel_ip_v4 // empty' "$d/metadata.json" 2>/dev/null)
        [[ -n "$ip" ]] && used_ips["$ip"]=1
      fi
    done
    
    # Scan WG Config
    if [[ -f "$WG_CONFIG" ]]; then
      while read -r ip_suffix; do
        [[ -n "$ip_suffix" ]] && used_ips["${ipv4_prefix_main}.${ip_suffix}"]=1
      done < <(grep -oP "AllowedIPs\s*=\s*${ipv4_prefix_main//./\.}\.\K\d+\.\d+" "$WG_CONFIG" || true)
      
      # Exclude Server IP (assuming .1)
      used_ips["${ipv4_prefix_main}.0.1"]=1
    fi
    
    local found=false
    for oct3 in {0..255}; do
      local start_oct4=2
      [[ "$oct3" -eq 0 ]] && start_oct4=2
      for oct4 in $(seq $start_oct4 254); do
         local candidate="${ipv4_prefix_main}.${oct3}.${oct4}"
         if [[ -z "${used_ips[$candidate]:-}" ]]; then
           client_ip_v4="$candidate"
           found=true
           break 2
         fi
      done
    done
    
    [[ "$found" == "false" ]] && die "Нет свободных IP в подсети."
  fi
  
  # --- Generate IPv6 ---
  local oct3=$(echo "$client_ip_v4" | cut -d. -f3)
  local oct4=$(echo "$client_ip_v4" | cut -d. -f4)
  local hex_part=$(printf "%x:%x" "$oct3" "$oct4")
  local client_ip_v6=""
  [[ -n "$server_ip_v6" ]] && client_ip_v6="${ipv6_prefix_main}::${hex_part}"
  
  log_info "Назначен IP: $client_ip_v4 $([[ -n $client_ip_v6 ]] && echo "/ $client_ip_v6")"
  
  # --- Generate Keys ---
  mkdir -p "$dir"
  umask 077
  wg genkey > "$dir/client_private.key"
  wg pubkey < "$dir/client_private.key" > "$dir/client_public.key"
  local priv_key=$(cat "$dir/client_private.key")
  local pub_key=$(cat "$dir/client_public.key")
  
  # --- Configs ---
  local allowed_ips="0.0.0.0/0"
  local addr_str="$client_ip_v4/32"
  if [[ -n "$client_ip_v6" ]]; then
    allowed_ips="0.0.0.0/0, ::/0"
    addr_str="$client_ip_v4/32, $client_ip_v6/128"
  fi
  
  # 1. WireGuard Config (Dual Stack)
  cat > "$dir/${id}.conf" <<EOF
[Interface]
PrivateKey = $priv_key
Address = $addr_str
DNS = 1.1.1.1, 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $server_pub
Endpoint = 127.0.0.1:${CLIENT_WG_PORT:-13255}
AllowedIPs = $allowed_ips
PersistentKeepalive = 25
EOF
  chmod 600 "$dir/${id}.conf"
  
  cat > "$dir/wg-obfuscator.conf" <<EOF
[instance]
source-if = 127.0.0.1
source-lport = ${CLIENT_WG_PORT:-13255}
target = $SERVER_PUBLIC_IP_V4:${OBFUSCATOR_PORT:-51821}
key = ${OBFUSCATOR_KEY:-KEY}
masking = AUTO
verbose = INFO
idle-timeout = ${OBFUSCATOR_IDLE:-300}
max-dummy = ${OBFUSCATOR_DUMMY:-4}
EOF
  chmod 600 "$dir/wg-obfuscator.conf"
  
  cat > "$dir/metadata.json" <<EOF
{
  "client_id": "$id",
  "client_name": "$name",
  "tunnel_ip_v4": "$client_ip_v4",
  "tunnel_ip_v6": "$client_ip_v6",
  "public_key": "$pub_key",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "obfuscator_key": "${OBFUSCATOR_KEY:-}",
  "obfuscator_dummy": "${OBFUSCATOR_DUMMY:-4}",
  "obfuscator_idle": "${OBFUSCATOR_IDLE:-300}",
  "server_ip_v4": "$SERVER_PUBLIC_IP_V4",
  "server_port": "${OBFUSCATOR_PORT:-}"
}
EOF
  chmod 600 "$dir/metadata.json"
  
  # --- Apply to Server ---
  local peer_ips="$client_ip_v4/32"
  [[ -n "$client_ip_v6" ]] && peer_ips="$peer_ips, $client_ip_v6/128"
  
  cat >> "$WG_CONFIG" <<EOF

[Peer]
PublicKey = $pub_key
AllowedIPs = $peer_ips
EOF
  
  wg syncconf wg0 <(wg-quick strip wg0)
  log_success "Клиент $name создан."

  CLIENT_ARG="$id"
  action_package
  action_link
}

action_remove() {
  local id=$(resolve_client "$CLIENT_ARG")
  if [[ -z "$id" ]]; then die "Клиент не найден."; fi
  local dir="$CLIENTS_DIR/$id"
  
  log_info "Удаление клиента $id..."
  
  # 1. Remove Peer from WireGuard
  if [[ -f "$dir/client_public.key" ]]; then
    local pub=$(cat "$dir/client_public.key")
    # Using temp file for safety
    if grep -q "$pub" "$WG_CONFIG"; then
       # Complex sed to remove block? Or just generic approach.
       # Simplest reliable way in bash without dependencies:
       # Read file, skip the block.
       awk -v key="$pub" ' 
         BEGIN {RS=""; ORS="\n\n"}
         $0 !~ key {print $0}
       ' "$WG_CONFIG" > "$WG_CONFIG.tmp" && mv "$WG_CONFIG.tmp" "$WG_CONFIG"
       
       # Remove extra newlines
       sed -i '/^$/N;/^\n$/D' "$WG_CONFIG"
       
       wg syncconf wg0 <(wg-quick strip wg0)
       log_success "Peer удален из конфигурации."
    fi
  fi
  
  # 2. Cleanup Files
  rm -rf "$dir"
  rm -f "$PACKAGES_DIR/phobos-$id.tar.gz"
  
  # 3. Cleanup Tokens (Requires jq)
  if [[ -f "$TOKENS_FILE" ]] && command -v jq >/dev/null; then
    local tokens=$(jq -r ".[] | select(.client == \"$id\") | .token" "$TOKENS_FILE")
    for t in $tokens; do
       rm -f "$WWW_DIR/init/$t.sh"
       rm -rf "$WWW_DIR/packages/$t"
    done
    jq "map(select(.client != \"$id\"))" "$TOKENS_FILE" > "$TOKENS_FILE.tmp" && mv "$TOKENS_FILE.tmp" "$TOKENS_FILE"
  fi
  
  log_success "Клиент $id полностью удален."
}

action_package() {
  local id=$(resolve_client "$CLIENT_ARG")
  if [[ -z "$id" ]]; then die "Клиент не найден."; fi
  
  log_info "Сборка пакета для $id..."
  local dir="$CLIENTS_DIR/$id"
  local tmp=$(mktemp -d)
  local pkg_root="$tmp/phobos-$id"
  
  mkdir -p "$pkg_root/bin"
  
  # Copy Configs
  cp "$dir/${id}.conf" "$pkg_root/${id}.conf"
  cp "$dir/wg-obfuscator.conf" "$pkg_root/wg-obfuscator.conf"
  
  # Copy Binaries
  for arch in mipsel mips aarch64 armv7 x86_64; do
    [[ -f "$PHOBOS_DIR/bin/wg-obfuscator-$arch" ]] && cp "$PHOBOS_DIR/bin/wg-obfuscator-$arch" "$pkg_root/bin/"
  done
  
  local tpl_dir="$REPO_DIR/client/templates"
  
  if [[ -d "$tpl_dir" ]]; then
     cp "$tpl_dir/install-router.sh.template" "$pkg_root/install-router.sh"
     sed -i "s|{{CLIENT_NAME}}|${id}|g" "$pkg_root/install-router.sh"
     chmod +x "$pkg_root/install-router.sh"
     
     # Copy others
     for f in router-configure-wireguard router-configure-wireguard-openwrt health-check phobos-uninstall detect-router-arch 3xui; do
       [[ -f "$tpl_dir/$f.sh.template" ]] && cp "$tpl_dir/$f.sh.template" "$pkg_root/$f.sh" && chmod +x "$pkg_root/$f.sh"
     done
  else
     log_warn "Шаблоны не найдены в $tpl_dir"
  fi
  
  # Create README
  echo "Phobos Client Package for $id" > "$pkg_root/README.txt"
  echo "Date: $(date)" >> "$pkg_root/README.txt"
  
  find "$pkg_root" -type f ! -path "*/bin/*" -exec sed -i 's/\r$//' {} \;
  
  # Compress
  tar -C "$tmp" -czf "$PACKAGES_DIR/phobos-$id.tar.gz" "phobos-$id"
  rm -rf "$tmp"
  
  log_success "Пакет создан: $PACKAGES_DIR/phobos-$id.tar.gz"
}

action_check() {
  local id=$(resolve_client "$CLIENT_ARG")
  if [[ -z "$id" ]]; then die "Клиент не найден."; fi

  local dir="$CLIENTS_DIR/$id"
  local changes=()

  if [[ ! -f "$dir/metadata.json" ]]; then
    echo "metadata_missing"
    return 1
  fi

  local client_server_ip=$(jq -r '.server_ip_v4 // ""' "$dir/metadata.json")
  local client_obf_key=$(jq -r '.obfuscator_key // ""' "$dir/metadata.json")
  local client_obf_port=$(jq -r '.server_port // ""' "$dir/metadata.json")
  local client_obf_dummy=$(jq -r '.obfuscator_dummy // "4"' "$dir/metadata.json")
  local client_obf_idle=$(jq -r '.obfuscator_idle // "300"' "$dir/metadata.json")

  local client_wg_pubkey=""
  if [[ -f "$dir/${id}.conf" ]]; then
    client_wg_pubkey=$(grep "^PublicKey" "$dir/${id}.conf" | cut -d'=' -f2- | tr -d ' ')
  fi

  [[ "$client_server_ip" != "$SERVER_PUBLIC_IP_V4" ]] && changes+=("IP сервера: $client_server_ip -> $SERVER_PUBLIC_IP_V4")
  [[ "$client_obf_key" != "$OBFUSCATOR_KEY" ]] && changes+=("Ключ обфускатора: изменен")
  [[ "$client_obf_port" != "$OBFUSCATOR_PORT" ]] && changes+=("Порт обфускатора: $client_obf_port -> $OBFUSCATOR_PORT")
  [[ "$client_obf_dummy" != "$OBFUSCATOR_DUMMY" ]] && changes+=("Max dummy: изменен")
  [[ "$client_obf_idle" != "$OBFUSCATOR_IDLE" ]] && changes+=("Idle таймаут: изменен")
  [[ -n "$client_wg_pubkey" && "$client_wg_pubkey" != "$SERVER_WG_PUBLIC_KEY" ]] && changes+=("Публичный ключ WG: изменен")

  if [[ ${#changes[@]} -gt 0 ]]; then
    echo "ИЗМЕНЕНИЯ КОНФИГУРАЦИИ:"
    for c in "${changes[@]}"; do
      echo "  - $c"
    done
    return 1
  fi

  return 0
}

action_link() {
  local id=$(resolve_client "$CLIENT_ARG")
  if [[ -z "$id" ]]; then die "Клиент не найден."; fi
  local ttl="${EXTRA_ARG:-$TOKEN_TTL}"

  if ! command -v jq >/dev/null; then die "jq не установлен. Установите: apt-get install jq"; fi

  local token=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
  local exp=$(($(date +%s) + ttl))

  if [[ ! -f "$TOKENS_FILE" ]]; then
    echo "[]" > "$TOKENS_FILE"
  fi

  local clean_json=$(jq "map(select(.client != \"$id\"))" "$TOKENS_FILE")
  echo "$clean_json" | jq ". + [{\"client\": \"$id\", \"token\": \"$token\", \"expires\": $exp}]" > "$TOKENS_FILE.tmp" && mv "$TOKENS_FILE.tmp" "$TOKENS_FILE"

  local link_dir="$WWW_DIR/packages/$token"
  rm -rf "$link_dir"
  mkdir -p "$link_dir"
  ln -s "$PACKAGES_DIR/phobos-$id.tar.gz" "$link_dir/phobos-$id.tar.gz"

  mkdir -p "$WWW_DIR/init"
  local script_url="http://${SERVER_PUBLIC_IP_V4}:${HTTP_PORT:-80}/packages/$token/phobos-$id.tar.gz"

  cat > "$WWW_DIR/init/$token.sh" <<EOF
#!/bin/sh
url="$script_url"
dir="/tmp/phobos_install_\$\$"
mkdir -p "\$dir"
echo "Downloading..."
if command -v curl >/dev/null; then
  curl -L -s -o "\$dir/package.tar.gz" "\$url"
else
  wget -q -O "\$dir/package.tar.gz" "\$url"
fi
if [ ! -f "\$dir/package.tar.gz" ]; then echo "Download failed"; exit 1; fi
cd "\$dir"
tar xzf package.tar.gz
cd "phobos-$id"
chmod +x install-router.sh
./install-router.sh
EOF

  local cmd="curl -s http://${SERVER_PUBLIC_IP_V4}:${HTTP_PORT:-80}/init/$token.sh | sh"

  echo ""
  echo "=================================================="
  echo "КОМАНДА ДЛЯ УСТАНОВКИ (Действительна $(($ttl / 3600))ч)"
  echo "=================================================="
  echo "$cmd"
  echo "=================================================="
  echo ""
}

action_list() {
  printf "% -20s % -20s % -20s\n" "CLIENT ID" "IPv4" "CREATED"
  echo "------------------------------------------------------------"
  for d in "$CLIENTS_DIR"/*; do
    if [[ -d "$d" ]]; then
       local id=$(basename "$d")
       local ip="N/A"
       local date="N/A"
       if [[ -f "$d/metadata.json" ]]; then
         ip=$(jq -r '.tunnel_ip_v4 // "N/A"' "$d/metadata.json")
         date=$(jq -r '.created_at // "N/A"' "$d/metadata.json" | cut -d'T' -f1)
       fi
       printf "% -20s % -20s % -20s\n" "$id" "$ip" "$date"
    fi
  done
}

case "$CMD" in
  add) action_add ;;
  remove) action_remove ;;
  package) action_package ;;
  link) action_link ;;
  check) action_check ;;
  list) action_list ;;
  rebuild)
     action_remove
     action_add
     ;;
  *)
    echo "Usage: $0 {add|remove|list|package|link|check|rebuild}"
    exit 1
    ;;
esac
