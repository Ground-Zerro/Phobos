#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/vps-cleanup-tokens.sh"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 * * * *}"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if [[ ! -f "${CLEANUP_SCRIPT}" ]]; then
  echo "Ошибка: скрипт очистки не найден: ${CLEANUP_SCRIPT}"
  exit 1
fi

echo "=========================================="
echo "  Настройка автоматической очистки токенов"
echo "=========================================="
echo ""

echo "==> Проверка прав на выполнение скрипта очистки"
chmod +x "${CLEANUP_SCRIPT}"

echo "==> Настройка cron job"
echo "Расписание: ${CRON_SCHEDULE} (каждый час)"

CRON_JOB="${CRON_SCHEDULE} ${CLEANUP_SCRIPT} >> /opt/Phobos/logs/cleanup.log 2>&1"

TEMP_CRON=$(mktemp)
crontab -l > "${TEMP_CRON}" 2>/dev/null || true

if grep -qF "${CLEANUP_SCRIPT}" "${TEMP_CRON}"; then
  echo "Cron job уже существует, обновление..."
  grep -vF "${CLEANUP_SCRIPT}" "${TEMP_CRON}" > "${TEMP_CRON}.new" || true
  mv "${TEMP_CRON}.new" "${TEMP_CRON}"
fi

echo "${CRON_JOB}" >> "${TEMP_CRON}"

crontab "${TEMP_CRON}"
rm -f "${TEMP_CRON}"

echo "==> Проверка cron job"
echo ""
crontab -l | grep -F "${CLEANUP_SCRIPT}"
echo ""

echo "==> Тестовый запуск очистки"
"${CLEANUP_SCRIPT}"

echo ""
echo "=========================================="
echo "  Автоматическая очистка токенов настроена!"
echo "=========================================="
echo ""
echo "Расписание: ${CRON_SCHEDULE}"
echo "Скрипт очистки: ${CLEANUP_SCRIPT}"
echo "Лог файл: /opt/Phobos/logs/cleanup.log"
echo ""
echo "Управление:"
echo "  crontab -l                           - просмотр cron jobs"
echo "  crontab -e                           - редактирование cron jobs"
echo "  ${CLEANUP_SCRIPT}                    - ручной запуск очистки"
echo "  tail -f /opt/Phobos/logs/cleanup.log - просмотр логов очистки"
echo ""
