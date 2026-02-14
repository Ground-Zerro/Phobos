#!/bin/sh
set -e

PHOBOS_DIR=""
ROUTER_PLATFORM=""
SELECTED_CONF=""
IS_FULL_REMOVAL="1"
OBFUSCATOR_CONFIGS=""
OBFUSCATOR_CONFIG_COUNT=0

. "$(dirname "$0")/lib-client.sh"

collect_obf_configs() {
  OBFUSCATOR_CONFIGS=""
  OBFUSCATOR_CONFIG_COUNT=0
  [ -d "$PHOBOS_DIR" ] || return
  for f in "$PHOBOS_DIR"/wg-obfuscator*.conf; do
    [ -f "$f" ] || continue
    OBFUSCATOR_CONFIGS="${OBFUSCATOR_CONFIGS}$(basename "$f" .conf) "
    OBFUSCATOR_CONFIG_COUNT=$((OBFUSCATOR_CONFIG_COUNT + 1))
  done
}

get_config_label() {
  local obf_conf_base="$1"
  local idx_suffix="${obf_conf_base#wg-obfuscator}"
  local wg_iface="phobos${idx_suffix}"
  local addr=""
  if [ -f "/etc/wireguard/${wg_iface}.conf" ]; then
    addr=$(grep '^Address' "/etc/wireguard/${wg_iface}.conf" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' | cut -d'/' -f1 | cut -d',' -f1) || addr=""
  fi
  if [ -n "$addr" ]; then
    printf "%s  [интерфейс: %s, адрес: %s]" "$obf_conf_base" "$wg_iface" "$addr"
  else
    printf "%s" "$obf_conf_base"
  fi
}

select_config_to_remove() {
  collect_obf_configs

  if [ "$OBFUSCATOR_CONFIG_COUNT" -eq 0 ]; then
    IS_FULL_REMOVAL="1"
    SELECTED_CONF="all"
    return
  fi

  if [ "$OBFUSCATOR_CONFIG_COUNT" -eq 1 ]; then
    SELECTED_CONF=$(echo "$OBFUSCATOR_CONFIGS" | tr -s ' ' '\n' | grep -v '^$' | head -1)
    IS_FULL_REMOVAL="1"
    log "Обнаружена конфигурация: ${SELECTED_CONF}"
    return
  fi

  log ""
  log "Обнаружено несколько конфигураций:"
  log ""

  local i=1
  for conf_base in $OBFUSCATOR_CONFIGS; do
    local label
    label=$(get_config_label "$conf_base")
    log "  ${i}) ${label}"
    i=$((i + 1))
  done

  local all_num=$i
  log "  ${all_num}) Удалить все"
  log ""

  printf "Введите номер конфигурации для удаления: "
  read -r answer || answer=""

  case "$answer" in
    ''|*[!0-9]*)
      log "ОШИБКА: Неверный ввод"
      exit 1
      ;;
  esac

  if [ "$answer" -eq "$all_num" ]; then
    IS_FULL_REMOVAL="1"
    SELECTED_CONF="all"
    return
  fi

  if [ "$answer" -lt 1 ] || [ "$answer" -ge "$all_num" ]; then
    log "ОШИБКА: Номер вне диапазона"
    exit 1
  fi

  local selected_i=1
  for conf_base in $OBFUSCATOR_CONFIGS; do
    if [ "$selected_i" -eq "$answer" ]; then
      SELECTED_CONF="$conf_base"
      IS_FULL_REMOVAL="0"
      return
    fi
    selected_i=$((selected_i + 1))
  done
}

remove_single_obfuscator_instance() {
  local obf_conf_base="$1"
  local idx_suffix="${obf_conf_base#wg-obfuscator}"
  local binary_name="wg-obfuscator${idx_suffix}"
  local service_name="phobos-obfuscator${idx_suffix}"
  local wg_iface="phobos${idx_suffix}"

  log "Удаление конфигурации ${obf_conf_base}..."

  local link_file="$PHOBOS_DIR/${obf_conf_base}.link"
  local linked_client=""
  if [ -f "$link_file" ]; then
    linked_client=$(cat "$link_file" 2>/dev/null) || linked_client=""
  fi

  local privkey_fallback=""
  if [ -z "$linked_client" ] && [ "$ROUTER_PLATFORM" = "linux" ] && [ -f "/etc/wireguard/${wg_iface}.conf" ]; then
    privkey_fallback=$(grep '^PrivateKey' "/etc/wireguard/${wg_iface}.conf" 2>/dev/null | cut -d'=' -f2- | tr -d ' \t') || privkey_fallback=""
  fi

  for f in /opt/etc/init.d/S[0-9]*wg-obfuscator*; do
    [ -f "$f" ] || continue
    if grep -q "^PROCS=${binary_name}$" "$f" 2>/dev/null; then
      "$f" stop >/dev/null 2>&1 || true
      rm -f "$f"
      log "  ✓ Удален init-скрипт: $f"
      break
    fi
  done

  if [ -f "/etc/init.d/${service_name}" ]; then
    /etc/init.d/${service_name} stop >/dev/null 2>&1 || true
    /etc/init.d/${service_name} disable >/dev/null 2>&1 || true
    rm -f "/etc/init.d/${service_name}"
    log "  ✓ Удален procd init-скрипт: /etc/init.d/${service_name}"
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${service_name}.service" ]; then
    systemctl stop "${service_name}" >/dev/null 2>&1 || true
    systemctl disable "${service_name}" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${service_name}.service"
    log "  ✓ Удален systemd сервис: /etc/systemd/system/${service_name}.service"
  fi

  for dir in /opt/bin /usr/bin /usr/local/bin; do
    if [ -f "${dir}/${binary_name}" ]; then
      rm -f "${dir}/${binary_name}"
      log "  ✓ Удален бинарник: ${dir}/${binary_name}"
    fi
  done

  if [ "$ROUTER_PLATFORM" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop "wg-quick@${wg_iface}" >/dev/null 2>&1 || true
    systemctl disable "wg-quick@${wg_iface}" >/dev/null 2>&1 || true
    if [ -d "/etc/systemd/system/wg-quick@${wg_iface}.service.d" ]; then
      rm -rf "/etc/systemd/system/wg-quick@${wg_iface}.service.d"
      log "  ✓ Удален systemd override: wg-quick@${wg_iface}"
    fi
    if [ -f "/etc/wireguard/${wg_iface}.conf" ]; then
      rm -f "/etc/wireguard/${wg_iface}.conf"
      log "  ✓ Удален WireGuard конфиг: /etc/wireguard/${wg_iface}.conf"
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
  elif [ "$ROUTER_PLATFORM" = "keenetic" ]; then
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -n "$linked_client" ]; then
      local target_desc="Phobos-${linked_client}"
      log "  Удаление WireGuard интерфейса Keenetic: ${target_desc}..."
      local iface_list=$(curl -s "http://127.0.0.1:79/rci/show/interface" 2>/dev/null || echo "")
      if [ -n "$iface_list" ] && echo "$iface_list" | jq -e . >/dev/null 2>&1; then
        local iface_id=$(echo "$iface_list" | jq -r --arg desc "$target_desc" 'to_entries[] | select((.value.description? // "") == $desc) | .key' 2>/dev/null)
        if [ -n "$iface_id" ]; then
          local del_json=$(cat <<EOF
{
  "interface": {
    "$iface_id": {
      "no": true
    }
  }
}
EOF
)
          local del_result=$(echo "$del_json" | curl -s -X POST \
            -H "Content-Type: application/json" \
            -d @- \
            "http://127.0.0.1:79/rci/" 2>/dev/null)
          if echo "$del_result" | jq -e '.status == "error"' >/dev/null 2>&1; then
            local err_msg=$(echo "$del_result" | jq -r '.message // "Unknown error"' 2>/dev/null)
            log "  ОШИБКА при удалении ${iface_id}: $err_msg"
          else
            log "  ✓ Интерфейс ${iface_id} (${target_desc}) удален"
            curl -s -X POST \
              -H "Content-Type: application/json" \
              -d '{"system":{"configuration":{"save":{}}}}' \
              "http://127.0.0.1:79/rci/" >/dev/null 2>&1
            log "  ✓ Конфигурация сохранена"
          fi
        else
          log "  Интерфейс с описанием '${target_desc}' не найден"
        fi
      else
        log "  RCI API недоступен, пропускаем удаление интерфейса Keenetic"
      fi
    else
      log "  curl/jq не доступны или имя клиента не определено, пропускаем удаление интерфейса Keenetic"
    fi
  elif [ "$ROUTER_PLATFORM" = "openwrt" ]; then
    remove_wireguard_interfaces_openwrt
    remove_firewall_zone_openwrt
  fi

  if [ -f "$PHOBOS_DIR/${obf_conf_base}.conf" ]; then
    rm -f "$PHOBOS_DIR/${obf_conf_base}.conf"
    log "  ✓ Удален конфиг obfuscator: $PHOBOS_DIR/${obf_conf_base}.conf"
  fi

  [ -f "$link_file" ] && rm -f "$link_file"

  if [ -n "$linked_client" ] && [ -f "$PHOBOS_DIR/${linked_client}.conf" ]; then
    rm -f "$PHOBOS_DIR/${linked_client}.conf"
    log "  ✓ Удален конфиг клиента: ${linked_client}.conf"
  elif [ -n "$privkey_fallback" ]; then
    for client_conf in "$PHOBOS_DIR"/*.conf; do
      [ -f "$client_conf" ] || continue
      case "$(basename "$client_conf")" in
        wg-obfuscator*.conf) continue ;;
      esac
      if grep -qF "PrivateKey = ${privkey_fallback}" "$client_conf" 2>/dev/null; then
        rm -f "$client_conf"
        log "  ✓ Удален конфиг клиента: $(basename "$client_conf")"
        break
      fi
    done
  fi

  local remaining=0
  for f in "$PHOBOS_DIR"/*.conf; do
    [ -f "$f" ] && remaining=$((remaining + 1))
  done

  if [ "$remaining" -eq 0 ] && [ -d "$PHOBOS_DIR" ]; then
    rm -rf "$PHOBOS_DIR"
    log "  ✓ Удалена директория: $PHOBOS_DIR"
  fi
}

stop_obfuscator() {
  log "Остановка wg-obfuscator..."

  for f in /opt/etc/init.d/S[0-9]*wg-obfuscator*; do
    [ -f "$f" ] && "$f" stop >/dev/null 2>&1 || true
  done

  for f in /etc/init.d/phobos-obfuscator*; do
    if [ -f "$f" ]; then
      "$f" stop >/dev/null 2>&1 || true
      "$f" disable >/dev/null 2>&1 || true
    fi
  done

  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-units --no-legend --plain 'phobos-obfuscator*.service' | awk '{print $1}' | while read -r unit; do
      systemctl stop "$unit" >/dev/null 2>&1 || true
      systemctl disable "$unit" >/dev/null 2>&1 || true
    done
  fi

  if ps | grep -v grep | grep -q wg-obfuscator; then
    log "  Принудительное завершение процесса..."
    pkill -f wg-obfuscator >/dev/null 2>&1 || true
  fi
}

remove_wireguard_interfaces_keenetic() {
  log "Удаление WireGuard интерфейсов Phobos (Keenetic)..."

  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    log "  curl или jq не установлен, пропускаем удаление интерфейсов"
    return 0
  fi

  local interfaces=$(curl -s "http://127.0.0.1:79/rci/show/interface" 2>/dev/null || echo "")

  if [ -z "$interfaces" ] || ! echo "$interfaces" | jq -e . >/dev/null 2>&1; then
    log "  RCI API недоступен или вернул некорректный JSON"
    return 0
  fi

  local removed_count=0

  local phobos_interfaces=$(echo "$interfaces" | jq -r 'to_entries[] | select(.value.description? // "" | startswith("Phobos-")) | .key' 2>/dev/null)

  if [ -z "$phobos_interfaces" ]; then
    log "  Интерфейсы Phobos не найдены в системе"
    return 0
  fi

  echo "$phobos_interfaces" | while read -r interface_id; do
    if [ -z "$interface_id" ]; then
      continue
    fi

    local interface_desc=$(echo "$interfaces" | jq -r --arg id "$interface_id" '.[$id].description // "unknown"' 2>/dev/null)

    log "  Удаление интерфейса: $interface_id ($interface_desc)"

    local delete_json=$(cat <<EOF
{
  "interface": {
    "$interface_id": {
      "no": true
    }
  }
}
EOF
)

    local result=$(echo "$delete_json" | curl -s -X POST \
      -H "Content-Type: application/json" \
      -d @- \
      "http://127.0.0.1:79/rci/" 2>/dev/null)

    if echo "$result" | jq -e '.status == "error"' >/dev/null 2>&1; then
      local error_msg=$(echo "$result" | jq -r '.message // "Unknown error"' 2>/dev/null)
      log "  ОШИБКА при удалении $interface_id: $error_msg"
    else
      log "  ✓ Интерфейс $interface_id удален"
      removed_count=$((removed_count + 1))
    fi
  done

  local save_result=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"system":{"configuration":{"save":{}}}}' \
    "http://127.0.0.1:79/rci/" 2>/dev/null)

  if [ $removed_count -gt 0 ]; then
    log "✓ Удалено интерфейсов: $removed_count"
    log "✓ Конфигурация сохранена"
  fi
}

remove_wireguard_interfaces_openwrt() {
  log "Удаление WireGuard интерфейсов Phobos (OpenWRT)..."

  if ! command -v uci >/dev/null 2>&1; then
    log "  uci не установлен, пропускаем удаление интерфейсов"
    return 0
  fi

  local interface_name="phobos_wg"

  if uci -q get network.${interface_name} >/dev/null 2>&1; then
    log "  Удаление интерфейса: ${interface_name}"

    ifdown ${interface_name} >/dev/null 2>&1 || true

    uci -q delete network.${interface_name} || true

    local peers=$(uci show network 2>/dev/null | grep "wireguard_${interface_name}" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u)
    for peer in $peers; do
      uci -q delete network.$peer || true
    done

    uci commit network

    log "  ✓ Интерфейс ${interface_name} удален"
  else
    log "  Интерфейс ${interface_name} не найден"
  fi

  /etc/init.d/network reload >/dev/null 2>&1 || true
}

remove_firewall_zone_openwrt() {
  log "Удаление файрволл зоны Phobos (OpenWRT)..."

  if ! command -v uci >/dev/null 2>&1; then
    log "  uci не установлен, пропускаем удаление зоны"
    return 0
  fi

  local zone_name="phobos"

  if uci -q get firewall.${zone_name} >/dev/null 2>&1; then
    log "  Удаление зоны: ${zone_name}"
    uci -q delete firewall.${zone_name} || true
    uci commit firewall
    log "  ✓ Зона ${zone_name} удалена"

    /etc/init.d/firewall reload >/dev/null 2>&1 || true
  else
    log "  Зона ${zone_name} не найдена"
  fi
}

remove_wireguard_interfaces_linux() {
  log "Удаление WireGuard интерфейсов Phobos (Linux)..."

  if ! command -v systemctl >/dev/null 2>&1; then
    log "  systemctl не найден, пропускаем удаление интерфейсов"
    return 0
  fi

  for wg_conf in /etc/wireguard/phobos*.conf; do
    [ -f "$wg_conf" ] || continue
    local wg_interface
    wg_interface=$(basename "$wg_conf" .conf)

    if systemctl is-enabled --quiet wg-quick@${wg_interface} 2>/dev/null || systemctl is-active --quiet wg-quick@${wg_interface} 2>/dev/null; then
      log "  Остановка и удаление WireGuard сервиса: wg-quick@${wg_interface}"
      systemctl stop wg-quick@${wg_interface} >/dev/null 2>&1 || true
      systemctl disable wg-quick@${wg_interface} >/dev/null 2>&1 || true
      log "  ✓ Сервис wg-quick@${wg_interface} остановлен и отключен"
    fi

    if [ -d "/etc/systemd/system/wg-quick@${wg_interface}.service.d" ]; then
      log "  Удаление systemd override: /etc/systemd/system/wg-quick@${wg_interface}.service.d"
      rm -rf "/etc/systemd/system/wg-quick@${wg_interface}.service.d"
      log "  ✓ Systemd override удален"
    fi

    log "  Удаление конфигурации: $wg_conf"
    rm -f "$wg_conf"
    log "  ✓ Конфигурационный файл WireGuard удален"
  done

  systemctl daemon-reload >/dev/null 2>&1 || true
}

remove_files() {
  log "Удаление файлов Phobos..."

  for f in /opt/etc/init.d/S[0-9]*wg-obfuscator*; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "  ✓ Удален init-скрипт: $f"
    fi
  done

  for f in /etc/init.d/phobos-obfuscator*; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "  ✓ Удален procd init-скрипт: $f"
    fi
  done

  for f in /opt/bin/wg-obfuscator*; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "  ✓ Удален бинарник: $f"
    fi
  done

  for f in /usr/bin/wg-obfuscator*; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "  ✓ Удален бинарник: $f"
    fi
  done

  for f in /usr/local/bin/wg-obfuscator*; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "  ✓ Удален бинарник: $f"
    fi
  done

  local daemon_reload_needed=0
  for f in /etc/systemd/system/phobos-obfuscator*.service; do
    if [ -f "$f" ]; then
      rm -f "$f"
      daemon_reload_needed=1
      log "  ✓ Удален systemd сервис: $f"
    fi
  done

  if [ $daemon_reload_needed -eq 1 ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if [ -d "$PHOBOS_DIR" ]; then
    rm -rf "$PHOBOS_DIR"
    log "  ✓ Удалена директория: $PHOBOS_DIR"
  fi
}

show_final_info() {
  log ""
  log "╔════════════════════════════════════════════════════════════╗"
  log "║  Phobos успешно удален                                     ║"
  log "╚════════════════════════════════════════════════════════════╝"
  log ""
  log "Удалены компоненты:"
  log "  - wg-obfuscator (процесс, init-скрипт/сервис, бинарник)"
  log "  - WireGuard интерфейсы Phobos"
  log "  - Конфигурационные файлы"
  log ""
}

main() {
  ROUTER_PLATFORM=$(detect_router_platform)
  PHOBOS_DIR=$(detect_phobos_dir "$ROUTER_PLATFORM")

  log "==> Начало удаления Phobos (платформа: $ROUTER_PLATFORM)"
  log "==> Директория: $PHOBOS_DIR"

  check_root

  select_config_to_remove

  if [ "$IS_FULL_REMOVAL" = "1" ]; then
    stop_obfuscator

    if [ "$ROUTER_PLATFORM" = "keenetic" ]; then
      remove_wireguard_interfaces_keenetic
    elif [ "$ROUTER_PLATFORM" = "openwrt" ]; then
      remove_wireguard_interfaces_openwrt
      remove_firewall_zone_openwrt
    elif [ "$ROUTER_PLATFORM" = "linux" ]; then
      remove_wireguard_interfaces_linux
    else
      log "ПРЕДУПРЕЖДЕНИЕ: Неизвестная платформа, пропускаем удаление WireGuard интерфейсов"
    fi

    remove_files

    show_final_info
  else
    log "==> Удаление конфигурации: ${SELECTED_CONF}"
    remove_single_obfuscator_instance "$SELECTED_CONF"
    log ""
    log "╔════════════════════════════════════════════════════════════╗"
    log "║  Конфигурация успешно удалена                              ║"
    log "╚════════════════════════════════════════════════════════════╝"
    log ""
  fi

  log "==> Удаление завершено."
}

main "$@"
