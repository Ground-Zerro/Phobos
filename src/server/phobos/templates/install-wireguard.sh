install_wireguard_linux() {
  if ! command -v apt-get >/dev/null 2>&1; then
    msg "ОШИБКА: apt-get не найден (требуется Ubuntu/Debian)"
    return 1
  fi
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y wireguard wireguard-tools resolvconf net-tools >/dev/null 2>&1
}

configure_wireguard_linux() {
  local wg_interface="${OBF_WG_IFACE}"
  local wg_config_dir="/etc/wireguard"
  mkdir -p "$wg_config_dir"

  cp "$PHOBOS_DIR/${CLIENT_NAME}.conf" "$wg_config_dir/${wg_interface}.conf"
  chmod 600 "$wg_config_dir/${wg_interface}.conf"

  local client_ip
  client_ip=$(grep '^Address' "$wg_config_dir/${wg_interface}.conf" | cut -d'=' -f2 | tr -d ' ' | cut -d',' -f1 | cut -d'/' -f1)
  local route_target
  route_target=$(echo "$client_ip" | cut -d'.' -f1-2).0.0/16

  sed -i '/^MTU/a Table = off' "$wg_config_dir/${wg_interface}.conf"
  sed -i "/^Table = off/a PostUp = ip route add $route_target dev %i" "$wg_config_dir/${wg_interface}.conf"
  sed -i "/^PostUp/a PostDown = ip route del $route_target dev %i || true" "$wg_config_dir/${wg_interface}.conf"

  mkdir -p "/etc/systemd/system/wg-quick@${wg_interface}.service.d"
  cat > "/etc/systemd/system/wg-quick@${wg_interface}.service.d/override.conf" <<EOF
[Unit]
After=${OBF_SERVICE_NAME}.service
Requires=${OBF_SERVICE_NAME}.service
EOF

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable "wg-quick@${wg_interface}" >/dev/null 2>&1 || true
  systemctl start "wg-quick@${wg_interface}" >/dev/null 2>&1 || return 1

  sleep 3
  systemctl is-active --quiet "wg-quick@${wg_interface}"
}

configure_ufw_linux() {
  return 0
}
