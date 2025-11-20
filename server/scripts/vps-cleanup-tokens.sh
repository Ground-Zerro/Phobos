#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

cd /tmp 2>/dev/null || cd / 2>/dev/null || true

PHOBOS_DIR="/opt/Phobos"
WWW_DIR="${PHOBOS_DIR}/www"
TOKENS_DIR="${PHOBOS_DIR}/tokens"
TOKENS_FILE="${TOKENS_DIR}/tokens.json"
LOG_FILE="${PHOBOS_DIR}/logs/cleanup.log"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Ошибка: утилита 'jq' не установлена"
  echo "Установите jq командой: apt-get install -y jq"
  exit 1
fi

mkdir -p "${PHOBOS_DIR}/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

if [[ ! -f "${TOKENS_FILE}" ]]; then
  log "tokens.json не найден, создаем новый"
  mkdir -p "${TOKENS_DIR}"
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
  log "Создан пустой tokens.json, нечего очищать"
  exit 0
fi

if [[ ! -s "${TOKENS_FILE}" ]]; then
  log "tokens.json пустой, инициализируем"
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
  log "tokens.json инициализирован, нечего очищать"
  exit 0
fi

if ! jq empty "${TOKENS_FILE}" 2>/dev/null; then
  log "tokens.json поврежден, создаем резервную копию и пересоздаем"
  cp "${TOKENS_FILE}" "${TOKENS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  echo "[]" > "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
  log "tokens.json восстановлен, нечего очищать"
  exit 0
fi

CURRENT_TIME=$(date +%s)
log "Запуск очистки просроченных токенов"

EXPIRED_COUNT=0
ACTIVE_COUNT=0

jq -c '.[]' "${TOKENS_FILE}" | while IFS= read -r token_obj; do
  TOKEN=$(echo "${token_obj}" | jq -r '.token')
  EXPIRES_AT=$(echo "${token_obj}" | jq -r '.expires_at')
  CLIENT=$(echo "${token_obj}" | jq -r '.client')

  if [[ ${EXPIRES_AT} -lt ${CURRENT_TIME} ]]; then
    log "Удаление просроченного токена: ${TOKEN} (клиент: ${CLIENT})"

    if [[ -d "${WWW_DIR}/packages/${TOKEN}" ]]; then
      rm -rf "${WWW_DIR}/packages/${TOKEN}"
      log "  Удален симлинк: ${WWW_DIR}/packages/${TOKEN}"
    fi

    if [[ -f "${WWW_DIR}/init/${TOKEN}.sh" ]]; then
      rm -f "${WWW_DIR}/init/${TOKEN}.sh"
      log "  Удален init-скрипт: ${WWW_DIR}/init/${TOKEN}.sh"
    fi

    EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
  else
    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
  fi
done

TEMP_FILE=$(mktemp)
jq --argjson current "${CURRENT_TIME}" \
   '[.[] | select(.expires_at >= $current)]' \
   "${TOKENS_FILE}" > "${TEMP_FILE}"

if jq empty "${TEMP_FILE}" 2>/dev/null; then
  mv "${TEMP_FILE}" "${TOKENS_FILE}"
  chmod 600 "${TOKENS_FILE}"
else
  log "Ошибка при создании нового файла токенов, оставляем старый"
  rm -f "${TEMP_FILE}"
fi

log "Очистка завершена: удалено ${EXPIRED_COUNT} токенов, активных ${ACTIVE_COUNT}"
