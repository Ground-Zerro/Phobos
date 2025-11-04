#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PHOBOS_DIR="/opt/Phobos"
WWW_DIR="${PHOBOS_DIR}/www"
SERVER_ENV="${PHOBOS_DIR}/server/server.env"

HTTP_PORT="${HTTP_PORT:-8080}"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
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
ExecStart=/usr/bin/python3 -m http.server ${HTTP_PORT} --bind 0.0.0.0
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

echo "==> Настройка firewall (ufw)"
if command -v ufw &> /dev/null; then
  if ufw status | grep -q "Status: active"; then
    echo "Открытие порта 22/tcp (SSH) в firewall"
    ufw allow 22/tcp
    echo "Открытие порта ${HTTP_PORT}/tcp в firewall"
    ufw allow ${HTTP_PORT}/tcp
    ufw reload
  else
    echo "UFW не активирован, пропуск настройки firewall"
  fi
else
  echo "UFW не установлен, пропуск настройки firewall"
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
echo "Следующий шаг:"
echo "  ${SCRIPT_DIR}/vps-generate-install-command.sh <client_name>"
echo ""
