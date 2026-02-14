#!/bin/bash

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
CYAN='\033[96m'
RESET='\033[0m'
BOLD='\033[1m'

print_status() {
  local message="$1"
  local status="${2:-info}"
  local prefix=""
  case "$status" in
    success) prefix="${GREEN}[OK]" ;;
    error)   prefix="${RED}[ERR]" ;;
    warning) prefix="${YELLOW}[WARN]" ;;
    info)    prefix="${BLUE}[INFO]" ;;
    debug)   prefix="${CYAN}[DBG]" ;;
  esac
  echo -e "${prefix} ${message}${RESET}"
}

check_dependencies() {
  local missing=()
  for cmd in jq sqlite3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    print_status "Installing missing dependencies: ${missing[*]}" "info"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y -qq "${missing[@]}" >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q "${missing[@]/sqlite3/sqlite}" >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y -q "${missing[@]/sqlite3/sqlite}" >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
      apk add --quiet "${missing[@]/sqlite3/sqlite}" >/dev/null 2>&1
    fi
    for cmd in "${missing[@]}"; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        print_status "Failed to install $cmd" "error"
        exit 1
      fi
    done
    print_status "Dependencies installed successfully" "success"
  fi
}

parse_wireguard_conf() {
  local config_path="$1"
  local section=""

  if [[ ! -f "$config_path" ]]; then
    print_status "File $config_path not found" "error"
    exit 1
  fi

  INTERFACE_PRIVATEKEY=""
  INTERFACE_ADDRESS=""
  INTERFACE_MTU="1420"
  PEER_PUBLICKEY=""
  PEER_ENDPOINT=""
  PEER_ALLOWEDIPS=""
  PEER_PRESHAREDKEY=""
  PEER_KEEPALIVE="0"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ "$line" == "["*"]" ]]; then
      section=$(echo "$line" | tr -d '[]' | tr '[:upper:]' '[:lower:]')
      continue
    fi

    if [[ "$line" == *"="* ]]; then
      local key=$(echo "$line" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      local value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [[ "$section" == "interface" ]]; then
        case "$key" in
          PrivateKey) INTERFACE_PRIVATEKEY="$value" ;;
          Address) INTERFACE_ADDRESS="$value" ;;
          MTU) INTERFACE_MTU="$value" ;;
        esac
      elif [[ "$section" == "peer" ]]; then
        case "$key" in
          PublicKey) PEER_PUBLICKEY="$value" ;;
          Endpoint) PEER_ENDPOINT="$value" ;;
          AllowedIPs) PEER_ALLOWEDIPS="$value" ;;
          PresharedKey|PreSharedKey) PEER_PRESHAREDKEY="$value" ;;
          PersistentKeepalive) PEER_KEEPALIVE="$value" ;;
        esac
      fi
    fi
  done < "$config_path"
}

extract_endpoint() {
  local endpoint="$1"
  if [[ "$endpoint" == "["*"]:"* ]]; then
    SERVER_ADDRESS=$(echo "$endpoint" | sed 's/^\[\([^]]*\)\]:.*/\1/')
    SERVER_PORT=$(echo "$endpoint" | sed 's/.*\]:\([0-9]*\).*/\1/')
  else
    SERVER_ADDRESS=$(echo "$endpoint" | rev | cut -d':' -f2- | rev)
    SERVER_PORT=$(echo "$endpoint" | rev | cut -d':' -f1 | rev)
  fi
  [[ -z "$SERVER_PORT" ]] && SERVER_PORT="51820"
}

build_local_addresses() {
  local addresses="$1"
  local result="[]"

  IFS=',' read -ra ADDR_ARRAY <<< "$addresses"
  for addr in "${ADDR_ARRAY[@]}"; do
    addr=$(echo "$addr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$addr" ]] && continue

    local ip_part="$addr"
    if [[ "$addr" == *"/"* ]]; then
      ip_part=$(echo "$addr" | cut -d'/' -f1)
    fi

    if [[ "$ip_part" == *":"* ]]; then
      result=$(echo "$result" | jq --arg ip "${ip_part}/128" '. + [$ip]')
    else
      result=$(echo "$result" | jq --arg ip "${ip_part}/32" '. + [$ip]')
    fi
  done

  echo "$result"
}

build_allowed_ips() {
  local allowed="$1"
  local result="[]"

  if [[ -z "$allowed" ]]; then
    echo '["0.0.0.0/0", "::/0"]'
    return
  fi

  IFS=',' read -ra IP_ARRAY <<< "$allowed"
  for ip in "${IP_ARRAY[@]}"; do
    ip=$(echo "$ip" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$ip" ]] && continue
    result=$(echo "$result" | jq --arg ip "$ip" '. + [$ip]')
  done

  if [[ "$result" == "[]" ]]; then
    echo '["0.0.0.0/0", "::/0"]'
  else
    echo "$result"
  fi
}

convert_to_xray_outbound() {
  local tag="${1:-Phobos}"

  extract_endpoint "$PEER_ENDPOINT"

  local local_addresses=$(build_local_addresses "$INTERFACE_ADDRESS")
  local allowed_ips=$(build_allowed_ips "$PEER_ALLOWEDIPS")

  local peer_config
  peer_config=$(jq -n \
    --arg pubkey "$PEER_PUBLICKEY" \
    --argjson allowed "$allowed_ips" \
    --arg endpoint "${SERVER_ADDRESS}:${SERVER_PORT}" \
    '{
      "publicKey": $pubkey,
      "allowedIPs": $allowed,
      "endpoint": $endpoint
    }')

  if [[ -n "$PEER_KEEPALIVE" && "$PEER_KEEPALIVE" != "0" ]]; then
    peer_config=$(echo "$peer_config" | jq --argjson ka "$PEER_KEEPALIVE" '. + {"keepAlive": $ka}')
  fi

  if [[ -n "$PEER_PRESHAREDKEY" ]]; then
    peer_config=$(echo "$peer_config" | jq --arg psk "$PEER_PRESHAREDKEY" '. + {"preSharedKey": $psk}')
  fi

  local mtu="${INTERFACE_MTU:-1420}"

  OUTBOUND_JSON=$(jq -n \
    --arg tag "$tag" \
    --argjson mtu "$mtu" \
    --arg secret "$INTERFACE_PRIVATEKEY" \
    --argjson addresses "$local_addresses" \
    --argjson peer "$peer_config" \
    '{
      "protocol": "wireguard",
      "settings": {
        "mtu": $mtu,
        "secretKey": $secret,
        "address": $addresses,
        "workers": 2,
        "peers": [$peer],
        "noKernelTun": true
      },
      "tag": $tag
    }')
}

get_default_xray_config() {
  cat <<'XRAY_CONFIG'
{
  "api": {
    "services": ["HandlerService", "StatsService", "LoggerService"],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"},
      "tag": "api"
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "settings": {}, "tag": "direct"},
    {"protocol": "blackhole", "settings": {}, "tag": "block"}
  ],
  "policy": {
    "levels": {"0": {"statsUserDownlink": true, "statsUserUplink": true}},
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true,
      "statsOutboundDownlink": true,
      "statsOutboundUplink": true
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"inboundTag": ["api"], "outboundTag": "api", "type": "field"},
      {"ip": ["geoip:private"], "outboundTag": "block", "type": "field"}
    ]
  },
  "stats": {}
}
XRAY_CONFIG
}

find_database() {
  local paths=(
    "/etc/x-ui/x-ui.db"
    "/usr/local/x-ui/x-ui.db"
    "/opt/x-ui/x-ui.db"
    "./x-ui.db"
  )

  for path in "${paths[@]}"; do
    if [[ -f "$path" ]]; then
      print_status "Database found: $path" "success" >&2
      echo "$path"
      return 0
    fi
  done

  return 1
}

diagnose_database() {
  local db_path="$1"

  local tables=$(sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null)
  print_status "Found tables: $tables" "debug" >&2

  if echo "$tables" | grep -q "settings"; then
    local keys=$(sqlite3 "$db_path" "SELECT key FROM settings;" 2>/dev/null)
    print_status "Keys in settings: $keys" "debug" >&2

    for key in xrayTemplateConfig xrayConfig xray_config config; do
      local result=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key = '$key';" 2>/dev/null)
      if [[ -n "$result" ]]; then
        print_status "Found config key: $key" "success" >&2
        echo "$key"
        return 0
      fi
    done
  fi

  return 1
}

write_setting_to_db() {
  local db_path="$1"
  local config_key="$2"
  local config_value="$3"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$config_value" > "$tmp"
  sqlite3 "$db_path" "INSERT OR REPLACE INTO settings (key, value) VALUES ('$config_key', readfile('$tmp'));"
  local ret=$?
  rm -f "$tmp"
  return $ret
}

import_via_database() {
  local db_path="$1"

  print_status "Importing to database..." "info"

  if [[ ! -f "$db_path" ]]; then
    print_status "Database not found: $db_path" "error"
    return 1
  fi

  local config_key=$(diagnose_database "$db_path")

  if [[ -z "$config_key" ]]; then
    print_status "Xray config not found in database, creating new..." "warning"

    local base_config=$(get_default_xray_config)
    local new_config=$(echo "$base_config" | jq --argjson ob "$OUTBOUND_JSON" '.outbounds = [$ob] + .outbounds')

    if write_setting_to_db "$db_path" "xrayTemplateConfig" "$new_config"; then
      print_status "Base Xray config created with outbound" "success"
      return 0
    else
      print_status "Failed to create config" "error"
      return 1
    fi
  fi

  local current_config=$(sqlite3 "$db_path" "SELECT value FROM settings WHERE key = '$config_key';" 2>/dev/null)

  if [[ -z "$current_config" ]]; then
    print_status "Xray config not found" "error"
    return 1
  fi

  if ! echo "$current_config" | jq . >/dev/null 2>&1; then
    print_status "Invalid JSON in config" "error"
    return 1
  fi

  local tag=$(echo "$OUTBOUND_JSON" | jq -r '.tag')
  local existing_tag=$(echo "$current_config" | jq -r --arg t "$tag" '.outbounds[]? | select(.tag == $t) | .tag' 2>/dev/null)

  if [[ -n "$existing_tag" ]]; then
    print_status "Outbound '$tag' exists, replacing..." "warning"
    current_config=$(echo "$current_config" | jq --arg t "$tag" '.outbounds = [.outbounds[] | select(.tag != $t)]')
  fi

  local new_config=$(echo "$current_config" | jq --argjson ob "$OUTBOUND_JSON" '.outbounds = [$ob] + .outbounds')

  if write_setting_to_db "$db_path" "$config_key" "$new_config"; then
    print_status "Outbound added to database" "success"
    return 0
  else
    print_status "Failed to update database" "error"
    return 1
  fi
}

restart_xui_service() {
  print_status "Restarting x-ui service..." "info"

  if systemctl restart x-ui 2>/dev/null; then
    sleep 1
    if systemctl is-active --quiet x-ui; then
      print_status "x-ui service restarted and active" "success"
      return 0
    fi
  fi

  for cmd in "service x-ui restart" "/etc/init.d/x-ui restart" "x-ui restart"; do
    if $cmd 2>/dev/null; then
      print_status "Service restarted via: $cmd" "success"
      return 0
    fi
  done

  print_status "Failed to restart service automatically" "error"
  print_status "Restart manually: systemctl restart x-ui" "info"
  return 1
}

main() {
  echo -e "\n${BOLD}=== WireGuard to 3x-ui Auto-Import Tool ===${RESET}\n"

  check_dependencies

  local config_path="$1"
  if [[ -z "$config_path" ]]; then
    echo -n "Path to wireguard.conf: "
    read config_path
  fi

  print_status "Parsing $config_path..." "info"
  parse_wireguard_conf "$config_path"

  print_status "Converting to Xray format..." "info"
  convert_to_xray_outbound "Phobos"

  echo -e "\n${BOLD}Outbound configuration:${RESET}"
  echo "$OUTBOUND_JSON" | jq .
  echo

  local db_path="/etc/x-ui/x-ui.db"
  if [[ ! -f "$db_path" ]]; then
    print_status "Database not found at: $db_path" "warning"
    db_path=$(find_database)
    if [[ -z "$db_path" ]]; then
      print_status "Database not found in standard locations" "error"
      print_status "Make sure 3x-ui is installed" "info"
      exit 1
    fi
  fi

  systemctl stop x-ui 2>/dev/null
  if ! import_via_database "$db_path"; then
    systemctl start x-ui 2>/dev/null
    print_status "Database import failed" "error"
    exit 1
  fi

  local output_path="${config_path%.*}_3xui_outbound.json"
  echo "$OUTBOUND_JSON" | jq . > "$output_path" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    print_status "JSON saved to: $output_path" "success"
  fi

  echo
  local restart_ok=0
  restart_xui_service && restart_ok=1

  echo
  print_status "Import completed successfully!" "success"
  echo
  print_status "${BOLD}Info:${RESET}" "info"
  print_status "  Outbound 'Phobos' added to config" "info"
  if [[ $restart_ok -eq 1 ]]; then
    print_status "  x-ui service restarted" "info"
  else
    print_status "  x-ui service needs manual restart" "warning"
  fi
  print_status "  JSON config saved to $output_path" "info"
  echo
  print_status "${BOLD}Verification:${RESET}" "info"
  print_status "  Open 3x-ui web panel" "info"
  print_status "  Go to Outbounds section" "info"
  print_status "  Verify 'Phobos' outbound is present" "info"
  echo
}

main "$@"
