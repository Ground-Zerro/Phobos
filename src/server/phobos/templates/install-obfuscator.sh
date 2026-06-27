stop_existing_instance() {
  if [ -f "/opt/etc/init.d/${OBF_INIT_NAME}" ]; then
    /opt/etc/init.d/${OBF_INIT_NAME} stop >/dev/null 2>&1 || true
  fi
  if [ -f "/etc/init.d/${OBF_SERVICE_NAME}" ]; then
    /etc/init.d/${OBF_SERVICE_NAME} stop >/dev/null 2>&1 || true
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/${OBF_SERVICE_NAME}.service" ]; then
    systemctl stop "${OBF_SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
}

install_obfuscator() {
  local arch="$1"
  local binary_name="wg-obfuscator-${arch}"

  stop_existing_instance

  if [ ! -f "bin/${binary_name}" ]; then
    msg "ОШИБКА: бинарник ${binary_name} не найден в архиве"
    ls -1 bin/ 2>/dev/null || true
    exit 1
  fi

  local target_path="/opt/bin/${OBF_BINARY_NAME}"
  [ "$ROUTER_PLATFORM" = "openwrt" ] && target_path="/usr/bin/${OBF_BINARY_NAME}"

  if [ "$ROUTER_PLATFORM" = "openwrt" ]; then
    mkdir -p /usr/bin
  else
    mkdir -p /opt/bin
  fi

  [ -f "$target_path" ] && rm "$target_path"
  cp "bin/${binary_name}" "$target_path"
  chmod +x "$target_path"
}

create_init_script() {
  mkdir -p /opt/etc/init.d
  cat > /opt/etc/init.d/${OBF_INIT_NAME} <<EOF
#!/bin/sh

ENABLED=yes
PROCS=${OBF_BINARY_NAME}
ARGS="--config $PHOBOS_DIR/${OBF_CONF_NAME}"
PREARGS=""
DESC=\$PROCS
PATH=/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
EOF
  chmod +x /opt/etc/init.d/${OBF_INIT_NAME}
}

start_obfuscator() {
  if [ -f "/opt/etc/init.d/${OBF_INIT_NAME}" ]; then
    /opt/etc/init.d/${OBF_INIT_NAME} start >/dev/null 2>&1 || true
  elif [ -f "/etc/init.d/${OBF_SERVICE_NAME}" ]; then
    /etc/init.d/${OBF_SERVICE_NAME} start >/dev/null 2>&1 || true
    /etc/init.d/${OBF_SERVICE_NAME} enable >/dev/null 2>&1 || true
  fi

  sleep 2

  if command -v pidof >/dev/null 2>&1 && pidof "${OBF_BINARY_NAME}" >/dev/null 2>&1; then
    return 0
  fi
  if command -v pgrep >/dev/null 2>&1 && pgrep -f "${OBF_BINARY_NAME}" >/dev/null 2>&1; then
    return 0
  fi
  if ps w 2>/dev/null | grep -v grep | grep -q "${OBF_BINARY_NAME}"; then
    return 0
  fi
  if ps 2>/dev/null | grep -v grep | grep -q "${OBF_BINARY_NAME}"; then
    return 0
  fi
  if [ -f "/opt/etc/init.d/${OBF_INIT_NAME}" ]; then
    /opt/etc/init.d/${OBF_INIT_NAME} status 2>&1 | grep -q "alive" && return 0
  fi
  if [ -f "/etc/init.d/${OBF_SERVICE_NAME}" ]; then
    /etc/init.d/${OBF_SERVICE_NAME} status >/dev/null 2>&1 && return 0
  fi
  return 1
}

create_procd_init_script() {
  cat > /etc/init.d/${OBF_SERVICE_NAME} <<EOF
#!/bin/sh /etc/rc.common

START=$((49 + SLOT))
STOP=$((51 + SLOT))

USE_PROCD=1

PROG=/usr/bin/${OBF_BINARY_NAME}
CONFIG_FILE=${PHOBOS_DIR}/${OBF_CONF_NAME}

start_service() {
  if [ ! -f "\$PROG" ]; then
    echo "Error: wg-obfuscator not found at \$PROG"
    return 1
  fi

  if [ ! -f "\$CONFIG_FILE" ]; then
    echo "Error: config not found at \$CONFIG_FILE"
    return 1
  fi

  procd_open_instance
  procd_set_param command \$PROG --config \$CONFIG_FILE
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF
  chmod +x /etc/init.d/${OBF_SERVICE_NAME}
}

create_systemd_obfuscator_service() {
  cat > /etc/systemd/system/${OBF_SERVICE_NAME}.service <<EOFS
[Unit]
Description=Phobos WireGuard Obfuscator (${CLIENT_NAME})
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/${OBF_BINARY_NAME} --config $PHOBOS_DIR/${OBF_CONF_NAME}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFS

  if [ ! -f "/usr/local/bin/${OBF_BINARY_NAME}" ]; then
    if [ -f "/opt/bin/${OBF_BINARY_NAME}" ]; then
      cp "/opt/bin/${OBF_BINARY_NAME}" "/usr/local/bin/${OBF_BINARY_NAME}"
      chmod +x "/usr/local/bin/${OBF_BINARY_NAME}"
    elif [ -f "/usr/bin/${OBF_BINARY_NAME}" ]; then
      cp "/usr/bin/${OBF_BINARY_NAME}" "/usr/local/bin/${OBF_BINARY_NAME}"
      chmod +x "/usr/local/bin/${OBF_BINARY_NAME}"
    fi
  fi

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable "${OBF_SERVICE_NAME}" >/dev/null 2>&1
  systemctl start "${OBF_SERVICE_NAME}" >/dev/null 2>&1

  local wait_count=0
  while [ $wait_count -lt 10 ]; do
    sleep 1
    systemctl is-active --quiet "${OBF_SERVICE_NAME}" && return 0
    wait_count=$((wait_count + 1))
  done
  return 1
}
