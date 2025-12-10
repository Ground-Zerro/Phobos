#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

OBFUSCATOR_LISTEN_PORT="${OBFUSCATOR_LISTEN_PORT:-}"
OBFUSCATOR_KEY="${OBFUSCATOR_KEY:-}"
WG_LOCAL_ENDPOINT="${WG_LOCAL_ENDPOINT:-127.0.0.1:51820}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
PHOBOS_DIR="/opt/Phobos"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "==> Остановка текущего wg-obfuscator (если запущен)..."
systemctl stop wg-obfuscator >/dev/null 2>&1 || true

generate_safe_port() {
  local exclude_port="${1:-}"
  local IANA_RESERVED_PORTS=(
    7 9 11 13 17 19 20 21 22 23 25 37 42 43 49 53 67 68
    69 70 79 80 88 101 102 110 111 113 119 123 135 137 138
    139 143 161 162 177 179 194 201 389 443 445 465 512 513
    514 515 520 587 631 636 873 902 989 990 992 993 995
  )
  local COMMONLY_USED_PORTS=(
    81 82 83 88 90 99 443 591 593 808 888 880 888 981 982 999
    989 990 991 992 993 994 995 222 2222
    23 25 26 465 587
    800 801 802 808 809 880 888 890 899
    330 336 433 543 544 545 550 554 558 591 636 800 808 873 989 990
    111 135 137 138 139 445 500 535 548 631 902 903
  )

  local attempts=0
  local max_attempts=1000

  while [[ $attempts -lt $max_attempts ]]; do
    local port=$((100 + RANDOM % 601))

    local is_reserved=0
    for reserved in "${IANA_RESERVED_PORTS[@]}"; do
      if [[ $port -eq $reserved ]]; then
        is_reserved=1
        break
      fi
    done

    if [[ $is_reserved -eq 1 ]]; then
      ((attempts++))
      continue
    fi

    for commonly_used in "${COMMONLY_USED_PORTS[@]}"; do
      if [[ $port -eq $commonly_used ]]; then
        is_reserved=1
        break
      fi
    done

    if [[ $is_reserved -eq 1 ]]; then
      ((attempts++))
      continue
    fi

    if [[ -n "$exclude_port" ]] && [[ $port -eq $exclude_port ]]; then
      ((attempts++))
      continue
    fi

    if ss -tlnp 2>/dev/null | grep -q ":$port " || ss -ulnp 2>/dev/null | grep -q ":$port "; then
      ((attempts++))
      continue
    fi

    echo "$port"
    return 0
  done

  echo "Ошибка: не удалось найти свободный порт после $max_attempts попыток" >&2
  return 1
}

if [[ ! -f /usr/local/bin/wg-obfuscator ]]; then
  echo "Ошибка: wg-obfuscator не установлен."
  echo "Сначала запустите vps-build-obfuscator.sh"
  exit 1
fi

mkdir -p "$PHOBOS_DIR/server"

if [[ -f "$PHOBOS_DIR/server/ip_addresses.env" ]]; then
  echo "==> Загрузка IP адресов из ip_addresses.env..."
  set +e
  source "$PHOBOS_DIR/server/ip_addresses.env" 2>/dev/null
  SOURCE_RESULT=$?
  set -e
  if [[ $SOURCE_RESULT -eq 0 ]]; then
    if [[ "$SERVER_PUBLIC_IP_V4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP_V4}"
    fi
    if [[ "$SERVER_PUBLIC_IP_V6" =~ ^[0-9a-fA-F:]+$ ]] && [[ ! "$SERVER_PUBLIC_IP_V6" =~ [^0-9a-fA-F:] ]] && [[ "$SERVER_PUBLIC_IP_V6" =~ : ]]; then
      SERVER_PUBLIC_IP_V6="${SERVER_PUBLIC_IP_V6}"
    else
      SERVER_PUBLIC_IP_V6=""
    fi
  else
    echo "Предупреждение: файл ip_addresses.env содержит некорректные данные, игнорируем"
    SERVER_PUBLIC_IP=""
    SERVER_PUBLIC_IP_V6=""
  fi
fi

if [[ -z "$SERVER_PUBLIC_IP" ]]; then
  echo "==> Определение публичного IPv4 адреса..."
  SERVER_PUBLIC_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipecho.net/plain)
  if [[ ! "$SERVER_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_PUBLIC_IP=""
  fi
  if [[ -z "$SERVER_PUBLIC_IP" ]]; then
    echo "Не удалось автоматически определить публичный IPv4. Укажите вручную:"
    read -p "Введите публичный IPv4 адрес VPS: " SERVER_PUBLIC_IP
  fi
fi

if [[ -z "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "==> Определение публичного IPv6 адреса (опционально)..."

  detect_ipv6_method1() {
    if ! ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
      return 1
    fi

    if ! ping6 -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1; then
      return 1
    fi

    for service in "api64.ipify.org" "ifconfig.co" "icanhazip.com"; do
      ipv6_result=$(curl -6 -s --connect-timeout 2 --max-time 2 "https://$service" 2>/dev/null | tr -d '[:space:]')

      if [[ "$ipv6_result" =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]] || \
         [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]] || \
         [[ "$ipv6_result" =~ ^:(:([0-9a-fA-F]{1,4})){1,7}$ ]] || \
         [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ ]]; then
        echo "$ipv6_result"
        return 0
      fi
    done

    return 1
  }

  detect_ipv6_method2() {
    if ! ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
      return 1
    fi

    for service in "ident.me" "ipv6.icanhazip.com" "v6.ident.me"; do
      ipv6_result=$(curl -6 -s --connect-timeout 2 --max-time 2 "https://$service" 2>/dev/null | tr -d '[:space:]')

      if [[ "$ipv6_result" =~ ^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$ ]] || \
         [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ ]] || \
         [[ "$ipv6_result" =~ ^:(:([0-9a-fA-F]{1,4})){1,7}$ ]] || \
         [[ "$ipv6_result" =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ ]]; then
        echo "$ipv6_result"
        return 0
      fi
    done

    return 1
  }

  if ip -6 addr show scope global 2>/dev/null | grep -q "inet6"; then
    echo "Локальный IPv6 интерфейс обнаружен, определение публичного адреса..."

    ipv6_method1=$(timeout 8 bash -c "$(declare -f detect_ipv6_method1); detect_ipv6_method1" 2>/dev/null || echo "")

    if [[ -n "$ipv6_method1" ]] && [[ "$ipv6_method1" =~ ^[0-9a-fA-F:]+$ ]]; then
      echo "Основной метод: $ipv6_method1"

      ipv6_method2=$(timeout 8 bash -c "$(declare -f detect_ipv6_method2); detect_ipv6_method2" 2>/dev/null || echo "")

      if [[ -n "$ipv6_method2" ]] && [[ "$ipv6_method2" =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "Резервный метод: $ipv6_method2"

        if [[ "$ipv6_method1" == "$ipv6_method2" ]]; then
          echo "IPv6 адрес достоверно определен: $ipv6_method1"
          SERVER_PUBLIC_IP_V6="$ipv6_method1"
        else
          echo "ВНИМАНИЕ: результаты методов различаются!"
          echo "Не удалось достоверно определить IPv6, используется $ipv6_method1"
          SERVER_PUBLIC_IP_V6="$ipv6_method1"
        fi
      else
        echo "Резервный метод не дал результата, используется: $ipv6_method1"
        SERVER_PUBLIC_IP_V6="$ipv6_method1"
      fi
    else
      echo "Основной метод не дал результата, пробуем резервный..."

      ipv6_method2=$(timeout 8 bash -c "$(declare -f detect_ipv6_method2); detect_ipv6_method2" 2>/dev/null || echo "")

      if [[ -n "$ipv6_method2" ]] && [[ "$ipv6_method2" =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "IPv6 адрес определен резервным методом: $ipv6_method2"
        SERVER_PUBLIC_IP_V6="$ipv6_method2"
      else
        echo "Оба метода не смогли определить публичный IPv6"
        SERVER_PUBLIC_IP_V6=""
      fi
    fi
  else
    echo "IPv6 интерфейс не обнаружен на сервере"
    SERVER_PUBLIC_IP_V6=""
  fi
fi

echo "Публичный IPv4 адрес: $SERVER_PUBLIC_IP"
if [[ -n "$SERVER_PUBLIC_IP_V6" ]]; then
  echo "Публичный IPv6 адрес: $SERVER_PUBLIC_IP_V6"
fi

if [[ -z "$OBFUSCATOR_LISTEN_PORT" ]]; then
  echo "==> Генерация случайного UDP порта для obfuscator (диапазон 100-700)..."
  OBFUSCATOR_LISTEN_PORT=$(generate_safe_port)
  if [[ $? -ne 0 ]]; then
    echo "Ошибка генерации порта obfuscator"
    exit 1
  fi
fi

echo "Порт obfuscator: $OBFUSCATOR_LISTEN_PORT/udp"

if [[ -z "$OBFUSCATOR_KEY" ]]; then
  echo "==> Генерация симметричного ключа обфускации..."
  OBFUSCATOR_KEY=$(head -c 3 /dev/urandom | base64 | tr -d '+/=' | head -c 3)
fi

echo "==> Сохранение параметров сервера..."

cat > "$PHOBOS_DIR/server/server.env" <<EOF
OBFUSCATOR_PORT=$OBFUSCATOR_LISTEN_PORT
OBFUSCATOR_KEY=$OBFUSCATOR_KEY
SERVER_PUBLIC_IP_V4=$SERVER_PUBLIC_IP
SERVER_PUBLIC_IP_V6=$SERVER_PUBLIC_IP_V6
SERVER_PUBLIC_IP=$SERVER_PUBLIC_IP
WG_LOCAL_ENDPOINT=$WG_LOCAL_ENDPOINT
TOKEN_TTL=3600
EOF

chmod 600 "$PHOBOS_DIR/server/server.env"

echo "==> Создание конфигурации wg-obfuscator..."

cat > "$PHOBOS_DIR/server/wg-obfuscator.conf" <<EOF
[instance]
source-if = 0.0.0.0
source-lport = $OBFUSCATOR_LISTEN_PORT
target = $WG_LOCAL_ENDPOINT
key = $OBFUSCATOR_KEY
masking = AUTO
verbose = INFO
idle-timeout = 86400
max-dummy = 4
EOF

chmod 600 "$PHOBOS_DIR/server/wg-obfuscator.conf"

echo "==> Создание systemd service..."

cat > /etc/systemd/system/wg-obfuscator.service <<EOF
[Unit]
Description=WireGuard Traffic Obfuscator
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wg-obfuscator --config $PHOBOS_DIR/server/wg-obfuscator.conf
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=wg-obfuscator

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "==> Запуск wg-obfuscator..."
systemctl enable wg-obfuscator
systemctl start wg-obfuscator

sleep 2

echo "==> Настройка UFW firewall..."
if command -v ufw &>/dev/null; then
  ufw allow ${OBFUSCATOR_LISTEN_PORT}/udp comment "Phobos Obfuscator" 2>/dev/null || true
  echo "  Порт ${OBFUSCATOR_LISTEN_PORT}/udp добавлен в исключения UFW"
else
  echo "  UFW не установлен, пропуск настройки"
fi

echo ""
echo "==> wg-obfuscator успешно установлен и запущен!"
echo ""
echo "Параметры obfuscator:"
echo "  Публичный порт: $OBFUSCATOR_LISTEN_PORT/udp"
echo "  Ключ обфускации: $OBFUSCATOR_KEY"
echo "  Переадресация на: $WG_LOCAL_ENDPOINT"
echo ""
echo "Файлы конфигурации:"
echo "  Параметры сервера: $PHOBOS_DIR/server/server.env"
echo "  Конфиг obfuscator: $PHOBOS_DIR/server/wg-obfuscator.conf"
echo ""
echo "Статус службы:"
systemctl status wg-obfuscator --no-pager -l
echo ""
echo "Проверка прослушиваемого порта:"
ss -ulpn | grep ":$OBFUSCATOR_LISTEN_PORT" || echo "Порт не прослушивается (проверьте логи)"
