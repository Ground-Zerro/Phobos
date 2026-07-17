#!/bin/sh
set -e

PHOBOS_DIR=""
ROUTER_PLATFORM=""

. "$(dirname "$0")/lib-client.sh"

remove_obfuscator_instance() {
  local bin="$1"
  local init="$2"
  local service="$3"

  if [ -n "$init" ] && [ -f "/opt/etc/init.d/${init}" ]; then
    "/opt/etc/init.d/${init}" stop >/dev/null 2>&1 || true
    rm -f "/opt/etc/init.d/${init}"
    log "  ✓ Удалён init-скрипт: /opt/etc/init.d/${init}"
  fi

  if [ -n "$service" ] && [ -f "/etc/init.d/${service}" ]; then
    "/etc/init.d/${service}" stop >/dev/null 2>&1 || true
    "/etc/init.d/${service}" disable >/dev/null 2>&1 || true
    rm -f "/etc/init.d/${service}"
    log "  ✓ Удалён procd init: /etc/init.d/${service}"
  fi

  if [ -n "$service" ] && command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${service}.service" ]; then
    systemctl stop "${service}" >/dev/null 2>&1 || true
    systemctl disable "${service}" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${service}.service"
    systemctl daemon-reload >/dev/null 2>&1 || true
    log "  ✓ Удалён systemd сервис: ${service}"
  fi

  local dir
  for dir in /opt/bin /usr/bin /usr/local/bin; do
    if [ -n "$bin" ] && [ -f "${dir}/${bin}" ]; then
      rm -f "${dir}/${bin}"
      log "  ✓ Удалён бинарник: ${dir}/${bin}"
    fi
  done
}

remove_wg_interface_keenetic() {
  local desc="$1"

  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    log "  curl/jq недоступны, пропуск удаления интерфейса Keenetic"
    return 0
  fi

  local list
  list=$(curl -s "http://127.0.0.1:79/rci/show/interface" 2>/dev/null || echo "")
  if ! echo "$list" | jq -e . >/dev/null 2>&1; then
    log "  RCI API недоступен, пропуск удаления интерфейса"
    return 0
  fi

  local id
  id=$(echo "$list" | jq -r --arg d "$desc" 'to_entries[] | select((.value.description? // "") == $d) | .key' 2>/dev/null | head -1)
  if [ -z "$id" ]; then
    log "  Интерфейс Keenetic '${desc}' не найден"
    return 0
  fi

  printf '{"interface":{"%s":{"no":true}}}' "$id" | curl -s -X POST \
    -H "Content-Type: application/json" -d @- "http://127.0.0.1:79/rci/" >/dev/null 2>&1 || true
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"system":{"configuration":{"save":{}}}}' "http://127.0.0.1:79/rci/" >/dev/null 2>&1 || true
  log "  ✓ Интерфейс Keenetic ${id} (${desc}) удалён"
}

remove_wg_interface_openwrt() {
  local iface="$1"

  command -v uci >/dev/null 2>&1 || return 0

  ifdown "$iface" >/dev/null 2>&1 || true

  uci -q delete "network.wgpeer_${iface}" || true
  local section
  for section in $(uci show network 2>/dev/null | grep "=wireguard_${iface}$" | cut -d. -f2 | cut -d= -f1); do
    uci -q delete "network.${section}" || true
  done
  uci -q delete "network.${iface}" || true
  uci commit network

  if uci -q get "firewall.${iface}" >/dev/null 2>&1; then
    uci -q delete "firewall.${iface}" || true
    uci commit firewall
    /etc/init.d/firewall restart >/dev/null 2>&1 || true
  fi

  /etc/init.d/network restart >/dev/null 2>&1 || true
  log "  ✓ Интерфейс OpenWRT ${iface} удалён"
}

remove_socks5_openwrt() {
  [ -f /etc/redsocks.conf ] || [ -f /etc/nftables.d/30-phobos-socks5.nft ] || return 0

  log "  Удаление SOCKS5 (redsocks + nft redirect)..."
  if [ -x /etc/init.d/phobos-redsocks ]; then
    /etc/init.d/phobos-redsocks stop >/dev/null 2>&1 || true
    /etc/init.d/phobos-redsocks disable >/dev/null 2>&1 || true
  fi
  [ -x /etc/init.d/redsocks ] && /etc/init.d/redsocks stop >/dev/null 2>&1 || true
  [ -f /var/run/redsocks.pid ] && kill "$(cat /var/run/redsocks.pid)" 2>/dev/null || true
  pkill -f /usr/sbin/redsocks 2>/dev/null || true
  rm -f /var/run/redsocks.pid /etc/redsocks.conf /etc/nftables.d/30-phobos-socks5.nft /etc/init.d/phobos-redsocks
  nft delete chain inet fw4 phobos_socks5_dstnat 2>/dev/null || true
  nft delete chain inet fw4 phobos_socks5_input 2>/dev/null || true
  fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1 || true
  log "  ✓ SOCKS5 (redsocks) удалён"
}

remove_wg_interface_linux() {
  local iface="$1"

  command -v systemctl >/dev/null 2>&1 || return 0

  systemctl stop "wg-quick@${iface}" >/dev/null 2>&1 || true
  systemctl disable "wg-quick@${iface}" >/dev/null 2>&1 || true
  rm -rf "/etc/systemd/system/wg-quick@${iface}.service.d"
  rm -f "/etc/wireguard/${iface}.conf"
  systemctl daemon-reload >/dev/null 2>&1 || true
  log "  ✓ Интерфейс Linux ${iface} удалён"
}

remove_client() {
  local client="$1"
  local line
  line=$(registry_line_for_client "$client")

  if [ -z "$line" ]; then
    log "Клиент ${client} не найден в реестре"
    return 1
  fi

  local obf_conf obf_bin init service iface
  obf_conf=$(registry_field "$line" 4)
  obf_bin=$(registry_field "$line" 5)
  init=$(registry_field "$line" 6)
  service=$(registry_field "$line" 7)
  iface=$(registry_field "$line" 8)

  log "Удаление клиента: ${client}"

  remove_obfuscator_instance "$obf_bin" "$init" "$service"

  case "$ROUTER_PLATFORM" in
    keenetic) remove_wg_interface_keenetic "$iface" ;;
    openwrt)  remove_socks5_openwrt; remove_wg_interface_openwrt "$iface" ;;
    linux)    remove_wg_interface_linux "$iface" ;;
  esac

  rm -f "$PHOBOS_DIR/${obf_conf}"
  rm -f "$PHOBOS_DIR/${client}.conf"
  registry_remove_client "$client"

  log "  ✓ Клиент ${client} удалён"
}

remove_phobos_dir() {
  [ -d "$PHOBOS_DIR" ] || return 0
  rm -rf "$PHOBOS_DIR"
  log "✓ Удалена директория: $PHOBOS_DIR"
}

purge_without_registry() {
  log "Реестр не найден — полная очистка артефактов Phobos..."

  local f
  for f in /opt/etc/init.d/S[0-9]*wg-obfuscator /etc/init.d/phobos-obfuscator*; do
    [ -f "$f" ] || continue
    "$f" stop >/dev/null 2>&1 || true
    "$f" disable >/dev/null 2>&1 || true
    rm -f "$f"
    log "  ✓ Удалён init/сервис: $f"
  done

  if command -v systemctl >/dev/null 2>&1; then
    for f in /etc/systemd/system/phobos-obfuscator*.service; do
      [ -f "$f" ] || continue
      local unit
      unit=$(basename "$f")
      systemctl stop "$unit" >/dev/null 2>&1 || true
      systemctl disable "$unit" >/dev/null 2>&1 || true
      rm -f "$f"
      log "  ✓ Удалён systemd сервис: $unit"
    done
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  for f in /opt/bin/wg-obfuscator* /usr/bin/wg-obfuscator* /usr/local/bin/wg-obfuscator*; do
    [ -f "$f" ] || continue
    rm -f "$f"
    log "  ✓ Удалён бинарник: $f"
  done

  if command -v pkill >/dev/null 2>&1; then
    pkill -f wg-obfuscator >/dev/null 2>&1 || true
  fi

  remove_phobos_dir
}

remove_all() {
  local client
  for client in $(registry_clients); do
    [ -n "$client" ] && remove_client "$client"
  done
  remove_phobos_dir
}

select_and_remove() {
  local clients count
  clients=$(registry_clients)
  count=$(printf '%s\n' "$clients" | grep -vc '^$')

  if [ "$count" -eq 0 ]; then
    purge_without_registry
    return
  fi

  if [ "$count" -eq 1 ]; then
    remove_client "$clients"
    remove_phobos_dir
    return
  fi

  log ""
  log "Обнаружено несколько клиентов:"
  log ""

  local i=1 line port target
  for client in $clients; do
    line=$(registry_line_for_client "$client")
    port=$(registry_field "$line" 3)
    target=$(registry_field "$line" 9)
    log "  ${i}) ${client}  [порт ${port}, сервер ${target}]"
    i=$((i + 1))
  done

  local all_num=$i
  log "  ${all_num}) Удалить все"
  log ""

  printf "Введите номер для удаления: "
  read -r answer || answer=""

  case "$answer" in
    ''|*[!0-9]*)
      log "ОШИБКА: Неверный ввод"
      exit 1
      ;;
  esac

  if [ "$answer" -eq "$all_num" ]; then
    remove_all
    return
  fi

  if [ "$answer" -lt 1 ] || [ "$answer" -ge "$all_num" ]; then
    log "ОШИБКА: Номер вне диапазона"
    exit 1
  fi

  local selected=""
  i=1
  for client in $clients; do
    if [ "$i" -eq "$answer" ]; then
      selected="$client"
      break
    fi
    i=$((i + 1))
  done

  remove_client "$selected"

  if [ -z "$(registry_clients)" ]; then
    remove_phobos_dir
  fi
}

main() {
  ROUTER_PLATFORM=$(detect_router_platform)
  PHOBOS_DIR=$(detect_phobos_dir "$ROUTER_PLATFORM")

  log "==> Удаление Phobos (платформа: $ROUTER_PLATFORM)"
  log "==> Директория: $PHOBOS_DIR"

  check_root

  select_and_remove

  log ""
  log "╔════════════════════════════════════════════════════════════╗"
  log "║  Удаление завершено                                        ║"
  log "╚════════════════════════════════════════════════════════════╝"
  log ""
}

main "$@"
