install_wireguard_linux() {
  log "Установка WireGuard для Linux..."

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update || log "ПРЕДУПРЕЖДЕНИЕ: Не удалось обновить список пакетов"
    apt-get install -y wireguard wireguard-tools resolvconf net-tools || {
      log "ОШИБКА: Не удалось установить WireGuard"
      return 1
    }
  else
    log "ОШИБКА: apt-get не найден. Поддерживаются только Ubuntu/Debian"
    return 1
  fi

  log "✓ WireGuard установлен"
  return 0
}

configure_wireguard_linux() {
  log ""
  log "==> Настройка WireGuard через systemd..."

  local wg_interface="${OBF_WG_IFACE}"
  local wg_config_dir="/etc/wireguard"
  mkdir -p "$wg_config_dir"

  cp "$PHOBOS_DIR/${CLIENT_NAME}.conf" "$wg_config_dir/${wg_interface}.conf"
  chmod 600 "$wg_config_dir/${wg_interface}.conf"

  log "Настройка routing: VPN как запасной интерфейс..."

  local client_ip=$(grep '^Address' "$wg_config_dir/${wg_interface}.conf" | cut -d'=' -f2 | tr -d ' ' | cut -d',' -f1 | cut -d'/' -f1)
  local route_target=$(echo "$client_ip" | cut -d'.' -f1-2).0.0/16

  sed -i '/^MTU/a Table = off' "$wg_config_dir/${wg_interface}.conf"
  sed -i "/^Table = off/a PostUp = ip route add $route_target dev %i" "$wg_config_dir/${wg_interface}.conf"
  sed -i "/^PostUp/a PostDown = ip route del $route_target dev %i || true" "$wg_config_dir/${wg_interface}.conf"

  log "Настройка зависимости WireGuard от obfuscator..."
  mkdir -p "/etc/systemd/system/wg-quick@${wg_interface}.service.d"
  cat > "/etc/systemd/system/wg-quick@${wg_interface}.service.d/override.conf" <<EOF
[Unit]
After=${OBF_SERVICE_NAME}.service
Requires=${OBF_SERVICE_NAME}.service
EOF

  systemctl daemon-reload

  log "Включение и запуск WireGuard интерфейса ${wg_interface}..."
  systemctl enable wg-quick@${wg_interface} || log "ПРЕДУПРЕЖДЕНИЕ: Не удалось включить автозапуск"
  systemctl start wg-quick@${wg_interface} || {
    log "ОШИБКА: Не удалось запустить WireGuard"
    return 1
  }

  sleep 3

  if systemctl is-active --quiet wg-quick@${wg_interface}; then
    log "✓ WireGuard успешно запущен (интерфейс: ${wg_interface})"
    log "  VPN настроен как запасной интерфейс (не перехватывает системный трафик)"

    if wg show ${wg_interface} 2>/dev/null | grep -q "latest handshake"; then
      log "✓ Туннель установлен и работает"
    else
      log "  Ожидание установки туннеля..."
    fi

    return 0
  else
    log "ПРЕДУПРЕЖДЕНИЕ: WireGuard может быть не запущен, проверьте статус"
    return 1
  fi
}

configure_ufw_linux() {
  log ""
  log "==> Проверка UFW firewall..."

  if ! command -v ufw >/dev/null 2>&1; then
    log "UFW не установлен, пропуск настройки"
    return 0
  fi

  log "✓ UFW обнаружен"
  log "  Клиентская конфигурация не требует открытия портов:"
  log "  - obfuscator слушает на 127.0.0.1:13255 (локальный интерфейс)"
  log "  - obfuscator делает исходящие соединения (разрешены по умолчанию)"

  if ufw status 2>/dev/null | grep -q "Status: active"; then
    log "  UFW активен, клиент будет работать корректно"
  else
    log "  UFW неактивен"
  fi
}
