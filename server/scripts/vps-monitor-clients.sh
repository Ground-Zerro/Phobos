#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PHOBOS_DIR="/opt/Phobos"
CLIENTS_DIR="${PHOBOS_DIR}/clients"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

if [[ ! -d "${CLIENTS_DIR}" ]]; then
  echo "Директория клиентов не найдена: ${CLIENTS_DIR}"
  echo ""
  read -p "Нажмите Enter для продолжения..."
  exit 0
fi

echo "=========================================="
echo "  Phobos Client Monitor"
echo "=========================================="
echo ""

if ! ip link show wg0 &>/dev/null; then
  echo "Ошибка: интерфейс WireGuard (wg0) не найден"
  exit 1
fi

CURRENT_TIME=$(date +%s)

CLIENT_DIRS=()
for client_dir in "${CLIENTS_DIR}"/*; do
  if [[ -d "${client_dir}" ]]; then
    CLIENT_DIRS+=("${client_dir}")
  fi
done

if [[ ${#CLIENT_DIRS[@]} -eq 0 ]]; then
  echo "Нет созданных клиентов."
  echo ""
  read -p "Нажмите Enter для продолжения..."
  exit 0
fi

echo "Дата проверки: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

printf "%-20s %-15s %-10s %-20s %-15s\n" "CLIENT" "TUNNEL IP" "STATUS" "LAST HANDSHAKE" "TRANSFER"
printf "%-20s %-15s %-10s %-20s %-15s\n" "--------------------" "---------------" "----------" "--------------------" "---------------"

for client_dir in "${CLIENT_DIRS[@]}"; do
  CLIENT_NAME=$(basename "${client_dir}")
  METADATA_FILE="${client_dir}/metadata.json"

  if [[ ! -f "${METADATA_FILE}" ]]; then
    continue
  fi

  CLIENT_PUBLIC_KEY=$(jq -r '.public_key' "${METADATA_FILE}")
  TUNNEL_IP=$(jq -r '.tunnel_ip_v4 // .tunnel_ip' "${METADATA_FILE}")

  HANDSHAKE_TIME=$(wg show wg0 latest-handshakes 2>/dev/null | grep "${CLIENT_PUBLIC_KEY}" | awk '{print $2}' || echo "0")
  TRANSFER=$(wg show wg0 transfer 2>/dev/null | grep "${CLIENT_PUBLIC_KEY}" | awk '{rx=$2; tx=$3; print rx","tx}' || echo "0,0")

  RX=$(echo "${TRANSFER}" | cut -d',' -f1)
  TX=$(echo "${TRANSFER}" | cut -d',' -f2)

  RX_MB=$(awk "BEGIN {printf \"%.2f\", ${RX}/1024/1024}")
  TX_MB=$(awk "BEGIN {printf \"%.2f\", ${TX}/1024/1024}")

  if [[ ${HANDSHAKE_TIME} -gt 0 ]]; then
    TIME_DIFF=$((CURRENT_TIME - HANDSHAKE_TIME))

    if [[ ${TIME_DIFF} -lt 180 ]]; then
      STATUS="ONLINE"
      LAST_SEEN="${TIME_DIFF}s ago"
    elif [[ ${TIME_DIFF} -lt 3600 ]]; then
      STATUS="IDLE"
      LAST_SEEN="$((TIME_DIFF / 60))m ago"
    else
      STATUS="OFFLINE"
      LAST_SEEN="$((TIME_DIFF / 3600))h ago"
    fi
  else
    STATUS="NEVER"
    LAST_SEEN="never connected"
  fi

  printf "%-20s %-15s %-10s %-20s %-15s\n" \
    "${CLIENT_NAME}" \
    "${TUNNEL_IP}" \
    "${STATUS}" \
    "${LAST_SEEN}" \
    "↓${RX_MB}M ↑${TX_MB}M"
done

echo ""

TOTAL_CLIENTS=${#CLIENT_DIRS[@]}
ONLINE_CLIENTS=$(wg show wg0 latest-handshakes 2>/dev/null | awk -v now="${CURRENT_TIME}" '$2 > (now - 180)' | wc -l)

echo "Статистика:"
echo "  Всего клиентов: ${TOTAL_CLIENTS}"
echo "  Онлайн (< 3 минуты): ${ONLINE_CLIENTS}"
echo ""
