#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PHOBOS_DIR="/opt/Phobos"
WWW_DIR="${PHOBOS_DIR}/www"
PACKAGES_DIR="${PHOBOS_DIR}/packages"
TOKENS_DIR="${PHOBOS_DIR}/tokens"
TOKENS_FILE="${TOKENS_DIR}/tokens.json"
SERVER_ENV="${PHOBOS_DIR}/server/server.env"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Утилита 'jq' не установлена. Устанавливаю..."
  apt-get update && apt-get install -y jq
  if ! command -v jq &> /dev/null; then
    echo "Ошибка: не удалось установить jq"
    exit 1
  fi
  echo "✓ jq успешно установлен"
fi

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 <client_name> [ttl_seconds]"
  echo ""
  echo "Аргументы:"
  echo "  client_name    - имя клиента (должен существовать)"
  echo "  ttl_seconds    - время жизни токена в секундах (по умолчанию: 3600 = 1 час)"
  echo ""
  echo "Пример:"
  echo "  $0 client1"
  echo "  $0 client1 3600"
  exit 1
fi

CLIENT_NAME="$1"
CLIENT_ID=$(echo "$CLIENT_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
CLIENT_DIR="${PHOBOS_DIR}/clients/${CLIENT_ID}"
PACKAGE_FILE="${PACKAGES_DIR}/phobos-${CLIENT_ID}.tar.gz"

if [[ $# -ge 2 ]]; then
  TOKEN_TTL="$2"
fi

if [[ ! -d "${CLIENT_DIR}" ]]; then
  echo "Ошибка: клиент '${CLIENT_NAME}' не найден"
  echo "Доступные клиенты:"
  ls -1 "${PHOBOS_DIR}/clients" 2>/dev/null || echo "  (нет клиентов)"
  exit 1
fi

if [[ ! -f "${PACKAGE_FILE}" ]]; then
  echo "Ошибка: пакет для клиента '${CLIENT_NAME}' не найден: ${PACKAGE_FILE}"
  echo "Создайте пакет командой: ${SCRIPT_DIR}/vps-client-add.sh ${CLIENT_NAME}"
  exit 1
fi

if [[ ! -f "${SERVER_ENV}" ]]; then
  echo "Ошибка: файл ${SERVER_ENV} не найден"
  exit 1
fi

source "${SERVER_ENV}"

TOKEN_TTL="${TOKEN_TTL:-3600}"

if [[ -z "${HTTP_PORT:-}" ]]; then
  echo "Ошибка: HTTP_PORT не указан в ${SERVER_ENV}"
  echo "Запустите: ${SCRIPT_DIR}/vps-start-http-server.sh"
  exit 1
fi

if [[ -z "${SERVER_PUBLIC_IP_V4:-}" ]]; then
  echo "Ошибка: SERVER_PUBLIC_IP_V4 не указан в ${SERVER_ENV}"
  exit 1
fi

echo "=========================================="
echo "  Генерация команды установки для клиента: ${CLIENT_NAME}"
echo "=========================================="
echo ""

mkdir -p "${TOKENS_DIR}"
mkdir -p "${WWW_DIR}/init"
mkdir -p "${WWW_DIR}/packages"

if [[ ! -f "${TOKENS_FILE}" ]]; then
  echo "==> Создание нового файла tokens.json"
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
elif [[ ! -s "${TOKENS_FILE}" ]]; then
  echo "==> Файл tokens.json пустой, инициализируем"
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
elif ! jq empty "${TOKENS_FILE}" 2>/dev/null; then
  echo "==> Файл tokens.json поврежден, пересоздаем"
  cp "${TOKENS_FILE}" "${TOKENS_FILE}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
fi

echo "==> Удаление старых токенов для клиента"
if [[ -f "${TOKENS_FILE}" ]] && command -v jq >/dev/null 2>&1; then
  TOKENS_TO_REMOVE=$(jq -r ".[] | select(.client == \"${CLIENT_ID}\") | .token" "${TOKENS_FILE}" 2>/dev/null || echo "")

  if [[ -n "$TOKENS_TO_REMOVE" ]]; then
    while IFS= read -r old_token; do
      [[ -z "$old_token" ]] && continue
      echo "Удаление токена: ${old_token}"
      rm -f "${WWW_DIR}/init/${old_token}.sh"
      rm -rf "${WWW_DIR}/packages/${old_token}"
    done <<< "$TOKENS_TO_REMOVE"

    jq "map(select(.client != \"${CLIENT_ID}\"))" "${TOKENS_FILE}" > "${TOKENS_FILE}.tmp"
    mv "${TOKENS_FILE}.tmp" "${TOKENS_FILE}"
  else
    echo "Старые токены не найдены"
  fi
fi

echo "==> Генерация уникального токена"
TOKEN=$(openssl rand -hex 16)
echo "Токен: ${TOKEN}"

echo "==> Генерация хеша для имени пакета"
PACKAGE_HASH=$(openssl rand -hex 8)
echo "Хеш пакета: ${PACKAGE_HASH}"

echo "==> Создание симлинка на пакет"
mkdir -p "${WWW_DIR}/packages/${TOKEN}"
ln -sf "${PACKAGE_FILE}" "${WWW_DIR}/packages/${TOKEN}/${PACKAGE_HASH}"

echo "==> Создание одноразового init-скрипта"
cat > "${WWW_DIR}/init/${TOKEN}.sh" <<'INIT_SCRIPT_EOF'
#!/bin/sh
set -e

CLIENT_NAME="__CLIENT_NAME_PLACEHOLDER__"
PACKAGE_URL="__PACKAGE_URL_PLACEHOLDER__"
INSTALL_DIR="/tmp/phobos-install-$$"

echo "=========================================="
echo "  Установка Phobos для клиента: ${CLIENT_NAME}"
echo "=========================================="
echo ""

echo "==> Создание временной директории"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

echo "==> Проверка наличия curl"
if ! command -v curl >/dev/null 2>&1; then
  echo "curl не найден, попытка установки..."
  if command -v opkg >/dev/null 2>&1; then
    opkg update && opkg install curl
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y curl
  elif command -v apk >/dev/null 2>&1; then
    apk update && apk add curl
  else
    echo "Ошибка: не удалось установить curl"
    exit 1
  fi
fi

echo "==> Генерация временного имени файла"
TEMP_FILE=$(echo "$$-$(date +%s)" | md5sum | cut -c1-16)

echo "==> Загрузка установочного пакета"
CURL_FLAGS="-L -C - -k"
if uname -a | grep -qi "OpenWrt\|LEDE\|ImmortalWrt\|Keenetic\|Netcraze"; then
  echo "Обнаружена встроенная система, используются флаги: следование переадресации, докачка, игнорирование сертификатов"
fi

if ! curl ${CURL_FLAGS} "${PACKAGE_URL}" -o "${TEMP_FILE}"; then
  echo "Ошибка: не удалось загрузить пакет"
  echo "Проверьте доступность сервера"
  exit 1
fi

echo "==> Распаковка пакета"
tar xzf "${TEMP_FILE}"
rm -f "${TEMP_FILE}"
cd "phobos-${CLIENT_NAME}"

echo "==> Запуск установки"
chmod +x install-router.sh
./install-router.sh

INSTALL_EXIT_CODE=$?

echo ""
if [ ${INSTALL_EXIT_CODE} -eq 0 ]; then
  echo "=========================================="
  echo "  ✓ Установка завершена успешно!"
  echo "=========================================="
else
  echo "=========================================="
  echo "  ⚠ Установка завершилась с ошибками"
  echo "=========================================="
fi

echo ""
echo "Очистка временных файлов..."
cd /
rm -rf "${INSTALL_DIR}"

exit ${INSTALL_EXIT_CODE}
INIT_SCRIPT_EOF

sed -i "s|__CLIENT_NAME_PLACEHOLDER__|${CLIENT_ID}|g" "${WWW_DIR}/init/${TOKEN}.sh"
sed -i "s|__PACKAGE_URL_PLACEHOLDER__|http://${SERVER_PUBLIC_IP_V4}:${HTTP_PORT}/packages/${TOKEN}/${PACKAGE_HASH}|g" "${WWW_DIR}/init/${TOKEN}.sh"

chmod +x "${WWW_DIR}/init/${TOKEN}.sh"

echo "==> Сохранение метаданных токена"

CREATED_AT=$(date +%s)
EXPIRES_AT=$((CREATED_AT + TOKEN_TTL))
EXPIRES_AT_HUMAN=$(date -d "@${EXPIRES_AT}" '+%Y-%m-%d %H:%M:%S')

if [[ ! -f "${TOKENS_FILE}" ]]; then
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
fi

TEMP_FILE=$(mktemp)
jq --arg token "${TOKEN}" \
   --arg client "${CLIENT_ID}" \
   --argjson created "${CREATED_AT}" \
   --argjson expires "${EXPIRES_AT}" \
   '. += [{
     "token": $token,
     "client": $client,
     "created_at": $created,
     "expires_at": $expires,
     "used": false
   }]' "${TOKENS_FILE}" > "${TEMP_FILE}"

if jq empty "${TEMP_FILE}" 2>/dev/null; then
  mv "${TEMP_FILE}" "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
  echo "✓ Токен сохранен в ${TOKENS_FILE}"
else
  echo "✗ Ошибка при сохранении токена"
  rm -f "${TEMP_FILE}"
  exit 1
fi

if jq -e --arg token "${TOKEN}" '.[] | select(.token == $token)' "${TOKENS_FILE}" >/dev/null 2>&1; then
  echo "✓ Токен проверен в базе данных"
else
  echo "✗ ВНИМАНИЕ: Токен не найден в базе данных после сохранения!"
fi

echo ""
echo "=========================================="
echo "  Команда установки сгенерирована!"
echo "=========================================="
echo ""
echo "Токен: ${TOKEN}"
echo "Срок действия: ${EXPIRES_AT_HUMAN} (${TOKEN_TTL} секунд)"
echo ""
echo "Отправьте клиенту следующую команду для установки:"
echo ""
echo "wget -O - http://${SERVER_PUBLIC_IP_V4}:${HTTP_PORT}/init/${TOKEN}.sh | sh"
echo ""
echo "ВАЖНО: Токен действителен до ${EXPIRES_AT_HUMAN}"
echo ""
