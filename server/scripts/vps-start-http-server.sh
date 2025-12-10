#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PHOBOS_DIR="/opt/Phobos"
WWW_DIR="${PHOBOS_DIR}/www"
SERVER_ENV="${PHOBOS_DIR}/server/server.env"

HTTP_PORT="${HTTP_PORT:-}"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "==> Остановка текущего HTTP сервера (если запущен)..."
systemctl stop phobos-http >/dev/null 2>&1 || true

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

if [[ -z "$HTTP_PORT" ]]; then
  OBFUSCATOR_PORT=""
  if [[ -f "$SERVER_ENV" ]]; then
    source "$SERVER_ENV"
    OBFUSCATOR_PORT="${OBFUSCATOR_PORT:-}"
  fi

  echo "==> Генерация случайного TCP порта для HTTP сервера (диапазон 100-700)..."
  HTTP_PORT=$(generate_safe_port "$OBFUSCATOR_PORT")
  if [[ $? -ne 0 ]]; then
    echo "Ошибка генерации порта HTTP сервера"
    exit 1
  fi
fi

echo "=========================================="
echo "  Настройка HTTP сервера для раздачи пакетов"
echo "=========================================="
echo ""

if ! command -v python3 &> /dev/null; then
  echo "Python3 не установлен. Установка..."
  apt-get update
  apt-get install -y python3
fi

echo "==> Создание структуры директорий"
mkdir -p "${WWW_DIR}"/{packages,init}
mkdir -p "${PHOBOS_DIR}/tokens"

echo "==> Установка безопасного HTTP сервера"
HTTP_SERVER_SCRIPT="${PHOBOS_DIR}/server/phobos-http-server.py"

if [[ -f "$SCRIPT_DIR/phobos-http-server.py" ]]; then
  cp "$SCRIPT_DIR/phobos-http-server.py" "$HTTP_SERVER_SCRIPT"
  chmod +x "$HTTP_SERVER_SCRIPT"
  echo "✓ HTTP сервер скрипт установлен: $HTTP_SERVER_SCRIPT"
elif [[ -f "$REPO_ROOT/server/scripts/phobos-http-server.py" ]]; then
  cp "$REPO_ROOT/server/scripts/phobos-http-server.py" "$HTTP_SERVER_SCRIPT"
  chmod +x "$HTTP_SERVER_SCRIPT"
  echo "✓ HTTP сервер скрипт установлен: $HTTP_SERVER_SCRIPT"
else
  echo "ОШИБКА: phobos-http-server.py не найден"
  exit 1
fi

echo "==> Создание index.html для корневой страницы"
cat > "${WWW_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Phobos Distribution Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        p { color: #666; line-height: 1.6; }
        code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Phobos Distribution Server</h1>
        <p>Сервер раздачи установочных пакетов Phobos.</p>
        <p>Для получения установочного пакета используйте токен, предоставленный администратором.</p>
    </div>
</body>
</html>
EOF

echo "==> Создание systemd unit файла"
cat > /etc/systemd/system/phobos-http.service <<EOF
[Unit]
Description=Phobos HTTP Distribution Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${WWW_DIR}
ExecStart=/usr/bin/python3 ${HTTP_SERVER_SCRIPT} ${HTTP_PORT} ${WWW_DIR}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "==> Перезагрузка systemd daemon"
systemctl daemon-reload

echo "==> Включение автозапуска HTTP сервера"
systemctl enable phobos-http.service

echo "==> Запуск HTTP сервера"
systemctl restart phobos-http.service

echo "==> Проверка статуса HTTP сервера"
sleep 2
if systemctl is-active --quiet phobos-http.service; then
  echo "✓ HTTP сервер успешно запущен"
else
  echo "✗ Ошибка запуска HTTP сервера"
  systemctl status phobos-http.service
  exit 1
fi

echo "==> Сохранение параметров HTTP сервера в ${SERVER_ENV}"
if [[ -f "${SERVER_ENV}" ]]; then
  if grep -q "^HTTP_PORT=" "${SERVER_ENV}"; then
    sed -i "s/^HTTP_PORT=.*/HTTP_PORT=${HTTP_PORT}/" "${SERVER_ENV}"
  else
    echo "HTTP_PORT=${HTTP_PORT}" >> "${SERVER_ENV}"
  fi
else
  echo "Предупреждение: ${SERVER_ENV} не найден"
fi

echo "==> Настройка UFW firewall..."
if command -v ufw &>/dev/null; then
  ufw allow ${HTTP_PORT}/tcp comment "Phobos HTTP Server" 2>/dev/null || true
  echo "  Порт ${HTTP_PORT}/tcp добавлен в исключения UFW"
else
  echo "  UFW не установлен, пропуск настройки"
fi

echo ""
echo "=========================================="
echo "  HTTP сервер успешно настроен!"
echo "=========================================="
echo ""
echo "HTTP сервер запущен на порту: ${HTTP_PORT}"
echo "Корневая директория: ${WWW_DIR}"
echo ""
echo "Управление сервисом:"
echo "  systemctl status phobos-http   - проверить статус"
echo "  systemctl restart phobos-http  - перезапустить"
echo "  systemctl stop phobos-http     - остановить"
echo "  journalctl -u phobos-http -f   - просмотр логов"
echo ""
