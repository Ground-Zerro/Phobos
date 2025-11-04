#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PHOBOS_DIR="/opt/Phobos"
SERVER_ENV="$PHOBOS_DIR/server/server.env"
OBF_CONFIG="$PHOBOS_DIR/server/wg-obfuscator.conf"
BACKUP_DIR="$PHOBOS_DIR/backups/obfuscator"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Требуются root привилегии. Запустите: sudo $0"
  exit 1
fi

NEW_PORT=""
NEW_IP=""
NEW_KEY=""
NEW_LOG_LEVEL=""
NEW_MASKING=""
NEW_IDLE_TIMEOUT=""
NEW_MAX_DUMMY=""
CHANGES_PENDING=false

load_current_config() {
  if [[ -f "$SERVER_ENV" ]]; then
    source "$SERVER_ENV"
  fi

  CURRENT_PORT="${OBFUSCATOR_PORT:-51821}"
  CURRENT_KEY="${OBFUSCATOR_KEY:-}"

  if [[ -f "$OBF_CONFIG" ]]; then
    CURRENT_IP=$(grep "^source-if" "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "0.0.0.0")
    CURRENT_LOG=$(grep "^verbose" "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "INFO")
    CURRENT_MASKING=$(grep "^masking" "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "AUTO")
    CURRENT_IDLE=$(grep "^idle-timeout" "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "86400")
    CURRENT_DUMMY=$(grep "^max-dummy" "$OBF_CONFIG" | cut -d'=' -f2- | tr -d ' ' || echo "4")
  else
    CURRENT_IP="0.0.0.0"
    CURRENT_LOG="INFO"
    CURRENT_MASKING="AUTO"
    CURRENT_IDLE="86400"
    CURRENT_DUMMY="4"
  fi
}

show_current_config() {
  load_current_config

  echo "ТЕКУЩАЯ КОНФИГУРАЦИЯ WG-OBFUSCATOR"
  echo "=========================================="
  echo ""
  echo "  Порт прослушивания:        $CURRENT_PORT (UDP)"
  echo "  IP интерфейса:             $CURRENT_IP"
  echo "  Ключ обфускации:           ${CURRENT_KEY:0:8}... (скрыт)"
  echo "  Уровень логирования:       $CURRENT_LOG"
  echo "  Режим маскировки:          $CURRENT_MASKING"
  echo "  Таймаут неактивности:      $CURRENT_IDLE сек"
  echo "  Максимум dummy-пакетов:    $CURRENT_DUMMY байт"
  echo ""

  if [[ "$CHANGES_PENDING" == "true" ]]; then
    echo "⚠  Есть несохраненные изменения!"
    echo ""
  fi
}

change_port() {
  load_current_config

  echo ""
  echo "==> Изменение порта прослушивания"
  echo ""
  echo "Текущий порт: $CURRENT_PORT"
  echo ""
  read -p "Введите новый порт (1024-65535) или 'r' для случайного: " port_input

  if [[ "$port_input" == "r" ]]; then
    NEW_PORT=$(shuf -i 10000-60000 -n 1)
    echo "Сгенерирован случайный порт: $NEW_PORT"
  else
    if [[ ! "$port_input" =~ ^[0-9]+$ ]] || [[ "$port_input" -lt 1024 ]] || [[ "$port_input" -gt 65535 ]]; then
      echo "Ошибка: порт должен быть в диапазоне 1024-65535"
      sleep 2
      return
    fi

    if ss -ulpn | grep -q ":$port_input "; then
      echo "Ошибка: порт $port_input уже занят"
      sleep 2
      return
    fi

    NEW_PORT="$port_input"
  fi

  CHANGES_PENDING=true
  echo "Порт будет изменен на $NEW_PORT (применить изменения для активации)"
  sleep 2
}

change_ip() {
  load_current_config

  echo ""
  echo "==> Изменение IP интерфейса"
  echo ""
  echo "Текущий IP: $CURRENT_IP"
  echo ""
  echo "Доступные IP адреса:"
  ip -4 addr | grep inet | awk '{print "  " $2}' | cut -d'/' -f1
  echo "  0.0.0.0 (все интерфейсы)"
  echo ""
  read -p "Введите IP адрес: " ip_input

  if [[ -z "$ip_input" ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  NEW_IP="$ip_input"
  CHANGES_PENDING=true
  echo "IP будет изменен на $NEW_IP (применить изменения для активации)"
  sleep 2
}

generate_new_key() {
  load_current_config

  echo ""
  echo "==> Генерация нового ключа обфускации"
  echo ""
  echo "Текущий ключ: ${CURRENT_KEY:0:12}..."
  echo ""
  echo "1) Автоматическая генерация"
  echo "2) Ручной ввод"
  echo "0) Отмена"
  echo ""
  read -p "Выберите: " choice

  case $choice in
    1)
      NEW_KEY=$(openssl rand -base64 3 | tr -d '+/=' | head -c 3)
      echo "Сгенерирован новый ключ: ${NEW_KEY:0:12}..."
      CHANGES_PENDING=true
      sleep 2
      ;;
    2)
      echo ""
      read -p "Введите новый ключ (минимум 1 символ, максимум 3): " key_input
      if [[ ${#key_input} -lt 1 ]] || [[ ${#key_input} -gt 3 ]]; then
        echo "Ошибка: длина ключа должна быть от 1 до 3 символов"
        sleep 2
        return
      fi
      NEW_KEY="$key_input"
      CHANGES_PENDING=true
      echo "Ключ будет изменен (применить изменения для активации)"
      sleep 2
      ;;
    0)
      return
      ;;
    *)
      echo "Неверный выбор"
      sleep 1
      ;;
  esac
}

change_log_level() {
  load_current_config

  echo ""
  echo "==> Изменение уровня логирования"
  echo ""
  echo "Текущий уровень: $CURRENT_LOG"
  echo ""
  echo "Доступные уровни:"
  echo "  TRACE - максимальная детализация (для отладки)"
  echo "  DEBUG - подробные логи"
  echo "  INFO  - стандартные логи"
  echo "  WARN  - только предупреждения"
  echo "  ERROR - только ошибки"
  echo ""
  read -p "Введите уровень: " level_input

  level_upper=$(echo "$level_input" | tr '[:lower:]' '[:upper:]')

  if [[ ! "$level_upper" =~ ^(TRACE|DEBUG|INFO|WARN|ERROR)$ ]]; then
    echo "Ошибка: недопустимый уровень"
    sleep 2
    return
  fi

  NEW_LOG_LEVEL="$level_upper"
  CHANGES_PENDING=true
  echo "Уровень логирования будет изменен на $NEW_LOG_LEVEL"
  sleep 2
}

change_masking_mode() {
  load_current_config

  echo ""
  echo "==> Изменение режима маскировки"
  echo ""
  echo "Текущий режим: $CURRENT_MASKING"
  echo ""
  echo "Доступные режимы:"
  echo "  AUTO - автоматический выбор (рекомендуется)"
  echo "  NONE - без маскировки"
  echo "  FULL - полная маскировка"
  echo ""
  read -p "Введите режим: " mode_input

  mode_upper=$(echo "$mode_input" | tr '[:lower:]' '[:upper:]')

  if [[ ! "$mode_upper" =~ ^(AUTO|NONE|FULL)$ ]]; then
    echo "Ошибка: недопустимый режим"
    sleep 2
    return
  fi

  NEW_MASKING="$mode_upper"
  CHANGES_PENDING=true
  echo "Режим маскировки будет изменен на $NEW_MASKING"
  sleep 2
}

change_idle_timeout() {
  load_current_config

  echo ""
  echo "==> Изменение таймаута неактивности"
  echo ""
  echo "Текущий таймаут: $CURRENT_IDLE секунд"
  echo ""
  echo "Рекомендуемые значения:"
  echo "  3600   - 1 час"
  echo "  86400  - 24 часа (по умолчанию)"
  echo "  604800 - 7 дней"
  echo ""
  read -p "Введите таймаут в секундах: " timeout_input

  if [[ ! "$timeout_input" =~ ^[0-9]+$ ]] || [[ "$timeout_input" -lt 60 ]]; then
    echo "Ошибка: таймаут должен быть числом >= 60"
    sleep 2
    return
  fi

  NEW_IDLE_TIMEOUT="$timeout_input"
  CHANGES_PENDING=true
  echo "Таймаут будет изменен на $NEW_IDLE_TIMEOUT секунд"
  sleep 2
}

change_max_dummy() {
  load_current_config

  echo ""
  echo "==> Изменение максимума dummy-пакетов"
  echo ""
  echo "Текущее значение: $CURRENT_DUMMY байт"
  echo ""
  echo "Диапазон: 0-1400 байт"
  echo "  0   - без dummy-пакетов"
  echo "  4   - минимальная маскировка (по умолчанию)"
  echo "  512 - средняя маскировка"
  echo "  1400 - максимальная маскировка"
  echo ""
  read -p "Введите значение (0-1400): " dummy_input

  if [[ ! "$dummy_input" =~ ^[0-9]+$ ]] || [[ "$dummy_input" -gt 1400 ]]; then
    echo "Ошибка: значение должно быть в диапазоне 0-1400"
    sleep 2
    return
  fi

  NEW_MAX_DUMMY="$dummy_input"
  CHANGES_PENDING=true
  echo "Максимум dummy-пакетов будет изменен на $NEW_MAX_DUMMY байт"
  sleep 2
}

show_changes_preview() {
  load_current_config

  echo ""
  echo "=========================================="
  echo "  ПРЕДПРОСМОТР ИЗМЕНЕНИЙ"
  echo "=========================================="
  echo ""

  local has_changes=false
  local critical_changes=false

  if [[ -n "$NEW_PORT" ]]; then
    echo "  Порт: $CURRENT_PORT → $NEW_PORT"
    has_changes=true
    critical_changes=true
  fi

  if [[ -n "$NEW_IP" ]]; then
    echo "  IP интерфейса: $CURRENT_IP → $NEW_IP"
    has_changes=true
  fi

  if [[ -n "$NEW_KEY" ]]; then
    echo "  Ключ: ${CURRENT_KEY:0:8}... → ${NEW_KEY:0:8}..."
    has_changes=true
    critical_changes=true
  fi

  if [[ -n "$NEW_LOG_LEVEL" ]]; then
    echo "  Логирование: $CURRENT_LOG → $NEW_LOG_LEVEL"
    has_changes=true
  fi

  if [[ -n "$NEW_MASKING" ]]; then
    echo "  Маскировка: $CURRENT_MASKING → $NEW_MASKING"
    has_changes=true
  fi

  if [[ -n "$NEW_IDLE_TIMEOUT" ]]; then
    echo "  Таймаут: $CURRENT_IDLE → $NEW_IDLE_TIMEOUT"
    has_changes=true
  fi

  if [[ -n "$NEW_MAX_DUMMY" ]]; then
    echo "  Dummy-пакеты: $CURRENT_DUMMY → $NEW_MAX_DUMMY"
    has_changes=true
  fi

  if [[ "$has_changes" == "false" ]]; then
    echo "  Нет изменений"
    echo ""
    return 1
  fi

  echo ""

  if [[ "$critical_changes" == "true" ]]; then
    local client_count=$(ls -1 "$PHOBOS_DIR/clients" 2>/dev/null | wc -l)

    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  ⚠  КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ                                ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  Изменение порта/ключа РАЗОРВЕТ связь со ВСЕМИ клиентами!║"
    echo "║                                                           ║"

    if [[ $client_count -gt 0 ]]; then
      echo "║  Потребуется переустановка на $client_count роутерах              ║"
      echo "║                                                           ║"
      for client_dir in "$PHOBOS_DIR/clients"/*; do
        if [[ -d "$client_dir" ]]; then
          client_id=$(basename "$client_dir")
          printf "║    - %-50s ║\n" "$client_id"
        fi
      done
    fi

    echo "╚══════════════════════════════════════════════════════════╝"
  fi

  echo ""
  return 0
}



apply_changes() {
  load_current_config

  if ! show_changes_preview; then
    read -p "Нажмите Enter для продолжения..."
    return
  fi

  local confirm_needed=false
  if [[ -n "$NEW_PORT" ]] || [[ -n "$NEW_KEY" ]]; then
    confirm_needed=true
    read -p "Введите YES для подтверждения критических изменений: " confirm
    if [[ "$confirm" != "YES" ]]; then
      echo "Отменено"
      sleep 1
      return
    fi
  fi

  echo ""
  if [[ "$confirm_needed" == "true" ]]; then
    echo "⚠  При изменении порта или ключа потребуется перенастроить всех клиентов!"
  fi
  read -p "Применить изменения? (y/n): " apply_confirm
  if [[ ! "$apply_confirm" =~ ^[Yy]$ ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  echo ""
  echo "==> Создание резервной копии..."
  mkdir -p "$BACKUP_DIR"
  local backup_file="$BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$backup_file" -C "$PHOBOS_DIR/server" server.env wg-obfuscator.conf 2>/dev/null || true
  echo "Резервная копия: $backup_file"

  echo ""
  echo "==> Применение изменений..."

  local final_port="${NEW_PORT:-$CURRENT_PORT}"
  local final_ip="${NEW_IP:-$CURRENT_IP}"
  local final_key="${NEW_KEY:-$CURRENT_KEY}"
  local final_log="${NEW_LOG_LEVEL:-$CURRENT_LOG}"
  local final_masking="${NEW_MASKING:-$CURRENT_MASKING}"
  local final_idle="${NEW_IDLE_TIMEOUT:-$CURRENT_IDLE}"
  local final_dummy="${NEW_MAX_DUMMY:-$CURRENT_DUMMY}"

  if [[ -n "$NEW_PORT" ]]; then
    sed -i "s/^OBFUSCATOR_PORT=.*/OBFUSCATOR_PORT=$final_port/" "$SERVER_ENV"
  fi

  if [[ -n "$NEW_KEY" ]]; then
    sed -i "s/^OBFUSCATOR_KEY=.*/OBFUSCATOR_KEY=$final_key/" "$SERVER_ENV"
  fi

  cat > "$OBF_CONFIG" <<EOF
[instance]
source-if = $final_ip
source-lport = $final_port
target = 127.0.0.1:51820
key = $final_key
masking = $final_masking
verbose = $final_log
idle-timeout = $final_idle
max-dummy = $final_dummy
EOF

  echo ""
  echo "==> Обновление firewall..."
  if command -v ufw >/dev/null 2>&1; then
    if [[ -n "$NEW_PORT" ]]; then
      ufw delete allow "$CURRENT_PORT/udp" 2>/dev/null || true
      ufw allow "$final_port/udp" || true
      echo "Firewall обновлен: порт $final_port/udp открыт"
    fi
  fi

  echo ""
  echo "==> Перезапуск службы wg-obfuscator..."
  systemctl restart wg-obfuscator

  sleep 2

  if systemctl is-active --quiet wg-obfuscator; then
    echo "✓ Служба wg-obfuscator успешно перезапущена"

    NEW_PORT=""
    NEW_IP=""
    NEW_KEY=""
    NEW_LOG_LEVEL=""
    NEW_MASKING=""
    NEW_IDLE_TIMEOUT=""
    NEW_MAX_DUMMY=""
    CHANGES_PENDING=false

    echo ""
    echo "✓ Изменения успешно применены!"
  else
    echo "✗ Ошибка запуска службы!"
    echo ""
    echo "Выполняется откат к резервной копии..."

    tar -xzf "$backup_file" -C "$PHOBOS_DIR/server" 2>/dev/null || true
    systemctl restart wg-obfuscator

    echo "Откат выполнен. Проверьте журналы: journalctl -u wg-obfuscator -n 50"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

reset_to_defaults() {
  echo ""
  echo "==> Сброс к настройкам по умолчанию"
  echo ""
  echo "Будут установлены следующие значения:"
  echo "  Порт:          случайный (10000-60000)"
  echo "  IP:            0.0.0.0"
  echo "  Ключ:          новый 3-символьный"
  echo "  Логирование:   INFO"
  echo "  Маскировка:    AUTO"
  echo "  Таймаут:       86400 сек"
  echo "  Dummy-пакеты:  4 байт"
  echo ""
  read -p "Продолжить? (y/n): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  NEW_PORT=$(shuf -i 10000-60000 -n 1)
  NEW_IP="0.0.0.0"
  NEW_KEY=$(openssl rand -base64 3 | tr -d '+/=' | head -c 3)
  NEW_LOG_LEVEL="INFO"
  NEW_MASKING="AUTO"
  NEW_IDLE_TIMEOUT="86400"
  NEW_MAX_DUMMY="4"
  CHANGES_PENDING=true

  echo ""
  echo "Настройки по умолчанию подготовлены. Примените изменения для активации."
  sleep 2
}

show_full_config() {
  echo ""
  echo "=========================================="
  echo "  ПОЛНАЯ КОНФИГУРАЦИЯ"
  echo "=========================================="
  echo ""

  if [[ -f "$OBF_CONFIG" ]]; then
    echo "==> $OBF_CONFIG"
    echo ""
    cat "$OBF_CONFIG"
    echo ""
  fi

  if [[ -f "$SERVER_ENV" ]]; then
    echo "==> $SERVER_ENV (obfuscator параметры)"
    echo ""
    grep "OBFUSCATOR" "$SERVER_ENV" || true
    echo ""
  fi

  if systemctl is-active --quiet wg-obfuscator; then
    echo "==> Статус службы"
    echo ""
    systemctl status wg-obfuscator --no-pager | head -10
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

mass_update_clients() {
  load_current_config

  echo ""
  echo "=========================================="
  echo "  МАССОВОЕ ОБНОВЛЕНИЕ КЛИЕНТОВ"
  echo "=========================================="
  echo ""

  local client_count=$(ls -1 "$PHOBOS_DIR/clients" 2>/dev/null | wc -l)

  if [[ $client_count -eq 0 ]]; then
    echo "Нет клиентов для обновления"
    sleep 2
    return
  fi

  echo "Будут обновлены $client_count клиентов:"
  echo ""

  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      echo "  - $(basename "$client_dir")"
    fi
  done

  echo ""
  read -p "Продолжить? (y/n): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  echo ""
  echo "==> Обновление конфигураций клиентов..."

  local updated=0

  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")

      if [[ -f "$client_dir/wg-obfuscator.conf" ]]; then
        sed -i "s/^target = .*/target = ${SERVER_PUBLIC_IP_V4:-$SERVER_PUBLIC_IP}:$CURRENT_PORT/" "$client_dir/wg-obfuscator.conf"
        sed -i "s/^key = .*/key = $CURRENT_KEY/" "$client_dir/wg-obfuscator.conf"
        sed -i "s/^max-dummy = .*/max-dummy = $CURRENT_DUMMY/" "$client_dir/wg-obfuscator.conf"
        echo "  ✓ $client_id обновлен"
        ((updated++))
      fi
    fi
  done

  echo ""
  echo "==> Пересоздание пакетов..."

  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      "$SCRIPT_DIR/vps-generate-package.sh" "$client_id" >/dev/null 2>&1 || true
      echo "  ✓ Пакет $client_id пересоздан"
    fi
  done

  echo ""
  echo "✓ Обновлено клиентов: $updated"
  echo ""
  echo "Теперь сгенерируйте новые токены установки для клиентов:"
  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      local client_id=$(basename "$client_dir")
      echo "  $SCRIPT_DIR/vps-generate-install-command.sh $client_id"
    fi
  done

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

check_health() {
  load_current_config

  echo ""
  echo "=========================================="
  echo "  ПРОВЕРКА ЗДОРОВЬЯ КОНФИГУРАЦИИ"
  echo "=========================================="
  echo ""

  local status_ok=true

  echo "==> Проверка порта..."
  if ss -ulpn | grep -q ":$CURRENT_PORT "; then
    echo "  ✓ Порт $CURRENT_PORT прослушивается"
  else
    echo "  ✗ Порт $CURRENT_PORT не прослушивается"
    status_ok=false
  fi

  echo ""
  echo "==> Проверка firewall..."
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "$CURRENT_PORT/udp"; then
      echo "  ✓ Порт $CURRENT_PORT/udp открыт в firewall"
    else
      echo "  ✗ Порт $CURRENT_PORT/udp не открыт в firewall"
      status_ok=false
    fi
  else
    echo "  - UFW не установлен"
  fi

  echo ""
  echo "==> Проверка WireGuard..."
  if ss -ulpn | grep -q "127.0.0.1:51820"; then
    echo "  ✓ WireGuard отвечает на 127.0.0.1:51820"
  else
    echo "  ✗ WireGuard не отвечает на 127.0.0.1:51820"
    status_ok=false
  fi

  echo ""
  echo "==> Проверка службы obfuscator..."
  if systemctl is-active --quiet wg-obfuscator; then
    echo "  ✓ Служба wg-obfuscator запущена"
  else
    echo "  ✗ Служба wg-obfuscator не запущена"
    status_ok=false
  fi

  echo ""
  echo "==> Проверка подключенных клиентов..."
  local connected=$(wg show wg0 | grep -c "peer:" || echo 0)
  echo "  Подключено клиентов: $connected"

  echo ""
  if [[ "$status_ok" == "true" ]]; then
    echo "✓ Все проверки пройдены успешно"
  else
    echo "⚠ Обнаружены проблемы"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

export_config() {
  load_current_config

  echo ""
  echo "==> Экспорт конфигурации"
  echo ""

  local export_file="$PHOBOS_DIR/backups/obfuscator-config-$(date +%Y%m%d-%H%M%S).json"
  mkdir -p "$PHOBOS_DIR/backups"

  cat > "$export_file" <<EOF
{
  "port": $CURRENT_PORT,
  "ip": "$CURRENT_IP",
  "key": "$CURRENT_KEY",
  "log_level": "$CURRENT_LOG",
  "masking": "$CURRENT_MASKING",
  "idle_timeout": $CURRENT_IDLE,
  "max_dummy": $CURRENT_DUMMY,
  "exported_at": "$(date -Iseconds)"
}
EOF

  echo "Конфигурация экспортирована: $export_file"
  echo ""
  read -p "Нажмите Enter для продолжения..."
}

import_config() {
  echo ""
  echo "==> Импорт конфигурации"
  echo ""

  read -p "Введите путь к JSON файлу: " import_file

  if [[ ! -f "$import_file" ]]; then
    echo "Ошибка: файл не найден"
    sleep 2
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "Ошибка: требуется jq"
    sleep 2
    return
  fi

  NEW_PORT=$(jq -r '.port' "$import_file")
  NEW_IP=$(jq -r '.ip' "$import_file")
  NEW_KEY=$(jq -r '.key' "$import_file")
  NEW_LOG_LEVEL=$(jq -r '.log_level' "$import_file")
  NEW_MASKING=$(jq -r '.masking' "$import_file")
  NEW_IDLE_TIMEOUT=$(jq -r '.idle_timeout' "$import_file")
  NEW_MAX_DUMMY=$(jq -r '.max_dummy' "$import_file")

  CHANGES_PENDING=true

  echo "Конфигурация загружена. Примените изменения для активации."
  sleep 2
}

show_config_header() {
  clear
  echo "=========================================="
  echo "         PHOBOS - Панель управления"
  echo "=========================================="
  echo ""
  echo "НАСТРОЙКА WG-OBFUSCATOR"
  echo ""
}

config_menu() {
  while true; do
    show_config_header
    show_current_config

    echo " 1) Изменить порт прослушивания"
    echo " 2) Изменить IP интерфейса"
    echo " 3) Сгенерировать новый ключ обфускации"
    echo " 4) Изменить уровень логирования"
    echo " 5) Изменить режим маскировки"
    echo " 6) Изменить таймаут неактивности"
    echo " 7) Изменить максимум dummy-пакетов"
    echo ""
    echo " 8) Предпросмотр изменений"
    echo " 9) Применить изменения и перезапустить службу"
    echo "10) Сброс к настройкам по умолчанию"
    echo "11) Показать полную конфигурацию"
    echo ""
    echo "12) Массовое обновление клиентов"
    echo "13) Проверка здоровья конфигурации"
    echo "14) Экспорт конфигурации"
    echo "15) Импорт конфигурации"
    echo ""
    echo " 0) Назад"
    echo ""

    if [[ -n "$NEW_PORT" ]] || [[ -n "$NEW_KEY" ]]; then
      echo "⚠  ВНИМАНИЕ: Изменение порта или ключа разорвет связь со всеми клиентами!"
      echo ""
    fi

    read -p "Выберите действие: " choice

    case $choice in
      1) change_port ;;
      2) change_ip ;;
      3) generate_new_key ;;
      4) change_log_level ;;
      5) change_masking_mode ;;
      6) change_idle_timeout ;;
      7) change_max_dummy ;;
      8) show_changes_preview; read -p "Нажмите Enter..." ;;
      9) apply_changes ;;
      10) reset_to_defaults ;;
      11) show_full_config ;;
      12) mass_update_clients ;;
      13) check_health ;;
      14) export_config ;;
      15) import_config ;;
      0) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

config_menu
