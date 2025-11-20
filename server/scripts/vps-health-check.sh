#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

cd /tmp 2>/dev/null || cd / 2>/dev/null || true

PHOBOS_DIR="/opt/Phobos"
SERVER_ENV="${PHOBOS_DIR}/server/server.env"
LOG_FILE="${PHOBOS_DIR}/logs/health-check.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERBOSE="${VERBOSE:-0}"
LOG_TO_FILE="${LOG_TO_FILE:-0}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  if [[ ${LOG_TO_FILE} -eq 1 ]]; then
    echo "${msg}" >> "${LOG_FILE}"
  fi
  if [[ ${VERBOSE} -eq 1 ]]; then
    echo "${msg}"
  fi
}

print_status() {
  local status="$1"
  local message="$2"

  if [[ "${status}" == "OK" ]]; then
    echo -e "${GREEN}✓${NC} ${message}"
  elif [[ "${status}" == "WARN" ]]; then
    echo -e "${YELLOW}⚠${NC} ${message}"
  else
    echo -e "${RED}✗${NC} ${message}"
  fi

  log "${status}: ${message}"
}

check_service() {
  local service_name="$1"
  local display_name="$2"

  if systemctl is-active --quiet "${service_name}"; then
    print_status "OK" "${display_name} запущен"
    return 0
  else
    print_status "FAIL" "${display_name} не запущен"
    return 1
  fi
}

check_port() {
  local port="$1"
  local protocol="$2"
  local description="$3"

  if ss -${protocol}lnp | grep -q ":${port} "; then
    print_status "OK" "${description} слушает порт ${port}/${protocol}"
    return 0
  else
    print_status "FAIL" "${description} не слушает порт ${port}/${protocol}"
    return 1
  fi
}

check_disk_space() {
  local path="$1"
  local threshold="$2"

  local usage=$(df -h "${path}" | awk 'NR==2 {print $5}' | sed 's/%//')

  if [[ ${usage} -lt ${threshold} ]]; then
    print_status "OK" "Использование диска ${path}: ${usage}%"
    return 0
  else
    print_status "WARN" "Использование диска ${path}: ${usage}% (порог: ${threshold}%)"
    return 1
  fi
}

check_wireguard_interface() {
  if ip link show wg0 &>/dev/null; then
    print_status "OK" "Интерфейс WireGuard (wg0) существует"

    local peer_count=$(wg show wg0 peers 2>/dev/null | wc -l)
    local active_peers=$(wg show wg0 latest-handshakes 2>/dev/null | awk '$2 > 0' | wc -l)

    echo "  └─ Всего пиров: ${peer_count}, активных: ${active_peers}"
    log "WireGuard peers: total=${peer_count}, active=${active_peers}"

    return 0
  else
    print_status "FAIL" "Интерфейс WireGuard (wg0) не найден"
    return 1
  fi
}

check_obfuscator_process() {
  if pgrep -x wg-obfuscator >/dev/null; then
    local pid=$(pgrep -x wg-obfuscator)
    local uptime=$(ps -p "${pid}" -o etime= | tr -d ' ')
    print_status "OK" "wg-obfuscator запущен (PID: ${pid}, uptime: ${uptime})"
    return 0
  else
    print_status "FAIL" "wg-obfuscator процесс не найден"
    return 1
  fi
}

echo "=========================================="
echo "  Phobos VPS Health Check"
echo "=========================================="
echo ""

if [[ ! -f "${SERVER_ENV}" ]]; then
  print_status "FAIL" "Файл конфигурации не найден: ${SERVER_ENV}"
  exit 1
fi

source "${SERVER_ENV}"

echo "==> Проверка сервисов"
check_service "wg-quick@wg0" "WireGuard"
check_service "wg-obfuscator" "wg-obfuscator"
check_service "phobos-http" "HTTP сервер"

echo ""
echo "==> Проверка сетевых портов"
check_port "51820" "u" "WireGuard (локальный)"
check_port "${OBFUSCATOR_PORT}" "u" "wg-obfuscator"
check_port "${HTTP_PORT}" "t" "HTTP сервер"

echo ""
echo "==> Проверка WireGuard"
check_wireguard_interface

echo ""
echo "==> Проверка процессов"
check_obfuscator_process

echo ""
echo "==> Проверка дискового пространства"
check_disk_space "/" 80
check_disk_space "${PHOBOS_DIR}" 80

echo ""
echo "==> Статистика клиентов"
if [[ -d "${PHOBOS_DIR}/clients" ]]; then
  TOTAL_CLIENTS=$(find "${PHOBOS_DIR}/clients" -mindepth 1 -maxdepth 1 -type d | wc -l)
  echo "  Всего клиентов: ${TOTAL_CLIENTS}"
  log "Total clients: ${TOTAL_CLIENTS}"
fi

if [[ -f "${PHOBOS_DIR}/tokens/tokens.json" ]]; then
  TOTAL_TOKENS=$(jq '. | length' "${PHOBOS_DIR}/tokens/tokens.json")
  ACTIVE_TOKENS=$(jq --argjson now "$(date +%s)" '[.[] | select(.expires_at >= $now)] | length' "${PHOBOS_DIR}/tokens/tokens.json")
  echo "  Всего токенов: ${TOTAL_TOKENS}, активных: ${ACTIVE_TOKENS}"
  log "Total tokens: ${TOTAL_TOKENS}, active: ${ACTIVE_TOKENS}"
fi

echo ""
echo "=========================================="
echo "  Проверка завершена"
echo "=========================================="
echo ""
