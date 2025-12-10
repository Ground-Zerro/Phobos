#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PHOBOS_DIR="/opt/Phobos"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Требуются root привилегии. Запустите: sudo phobos"
  exit 1
fi

show_header() {
  clear
  echo "=========================================="
  echo "         PHOBOS - Панель управления"
  echo "=========================================="
  echo ""
}

show_services_menu() {
  while true; do
    show_header
    echo "УПРАВЛЕНИЕ СЛУЖБАМИ"
    echo ""
    echo "  1) WireGuard - Старт"
    echo "  2) WireGuard - Стоп"
    echo "  3) WireGuard - Статус"
    echo "  4) WireGuard - Журнал (последние 20 записей)"
    echo ""
    echo "  5) Obfuscator - Старт"
    echo "  6) Obfuscator - Стоп"
    echo "  7) Obfuscator - Статус"
    echo "  8) Obfuscator - Журнал (последние 20 записей)"
    echo ""
    echo "  9) HTTP сервер - Старт"
    echo " 10) HTTP сервер - Стоп"
    echo " 11) HTTP сервер - Статус"
    echo " 12) HTTP сервер - Журнал (последние 20 записей)"
    echo ""
    echo "  0) Назад"
    echo ""
    read -p "Выберите действие: " choice

    case $choice in
      1) systemctl start wg-quick@wg0 && echo "WireGuard запущен" && sleep 2 ;;
      2) systemctl stop wg-quick@wg0 && echo "WireGuard остановлен" && sleep 2 ;;
      3) systemctl status wg-quick@wg0; read -p "Нажмите Enter для продолжения..." ;;
      4) journalctl -u wg-quick@wg0 -n 20 --no-pager; read -p "Нажмите Enter для продолжения..." ;;
      5) systemctl start wg-obfuscator && echo "Obfuscator запущен" && sleep 2 ;;
      6) systemctl stop wg-obfuscator && echo "Obfuscator остановлен" && sleep 2 ;;
      7) systemctl status wg-obfuscator; read -p "Нажмите Enter для продолжения..." ;;
      8) journalctl -u wg-obfuscator -n 20 --no-pager; read -p "Нажмите Enter для продолжения..." ;;
      9) systemctl start phobos-http && echo "HTTP сервер запущен" && sleep 2 ;;
      10) systemctl stop phobos-http && echo "HTTP сервер остановлен" && sleep 2 ;;
      11) systemctl status phobos-http; read -p "Нажмите Enter для продолжения..." ;;
      12) journalctl -u phobos-http -n 20 --no-pager; read -p "Нажмите Enter для продолжения..." ;;
      0) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

show_clients_list() {
  show_header
  echo "СПИСОК КЛИЕНТОВ"
  echo ""

  if [[ ! -d "$PHOBOS_DIR/clients" ]] || [[ -z "$(ls -A "$PHOBOS_DIR/clients" 2>/dev/null)" ]]; then
    echo "Нет созданных клиентов"
  else
    printf "%-20s %-20s %-24s %-20s\n" "CLIENT ID" "IPv4" "IPv6" "Date of creation"
    echo "--------------------------------------------------------------------------------"

    for client_dir in "$PHOBOS_DIR/clients"/*; do
      if [[ -d "$client_dir" ]]; then
        client_id=$(basename "$client_dir")

        if [[ -f "$client_dir/metadata.json" ]] && command -v jq >/dev/null 2>&1; then
          ipv4=$(jq -r '.tunnel_ip_v4 // "N/A"' "$client_dir/metadata.json")
          ipv6=$(jq -r '.tunnel_ip_v6 // "N/A"' "$client_dir/metadata.json")
        else
          ipv4="N/A"
          ipv6="N/A"
        fi

        if [[ -d "$client_dir" ]]; then
          creation_date=$(stat -c %y "$client_dir" 2>/dev/null | cut -d' ' -f1 || date -r "$client_dir" +%Y-%m-%d 2>/dev/null || echo "N/A")
        else
          creation_date="N/A"
        fi

        printf "%-20s %-20s %-24s %-20s\n" "$client_id" "$ipv4" "$ipv6" "$creation_date"
      fi
    done
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

select_client() {
  local selected_client=""

  if [[ ! -d "$PHOBOS_DIR/clients" ]] || [[ -z "$(ls -A "$PHOBOS_DIR/clients" 2>/dev/null)" ]]; then
    echo "Нет созданных клиентов" >&2
    return 1
  fi

  local clients=()
  local index=1

  echo "ДОСТУПНЫЕ КЛИЕНТЫ:" >&2
  echo "" >&2
  printf "%-5s %-20s %-20s %-24s %-20s\n" "№" "CLIENT ID" "IPv4" "IPv6" "Date of creation" >&2
  echo "--------------------------------------------------------------------------------------------" >&2

  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      client_id=$(basename "$client_dir")
      clients+=("$client_id")

      if [[ -f "$client_dir/metadata.json" ]] && command -v jq >/dev/null 2>&1; then
        ipv4=$(jq -r '.tunnel_ip_v4 // "N/A"' "$client_dir/metadata.json")
        ipv6=$(jq -r '.tunnel_ip_v6 // "N/A"' "$client_dir/metadata.json")
      else
        ipv4="N/A"
        ipv6="N/A"
      fi

      if [[ -d "$client_dir" ]]; then
        creation_date=$(stat -c %y "$client_dir" 2>/dev/null | cut -d' ' -f1 || date -r "$client_dir" +%Y-%m-%d 2>/dev/null || echo "N/A")
      else
        creation_date="N/A"
      fi

      printf "%-5s %-20s %-20s %-24s %-20s\n" "$index" "$client_id" "$ipv4" "$ipv6" "$creation_date" >&2
      ((index++))
    fi
  done

  echo "" >&2
  read -p "Введите номер клиента или его имя: " user_input

  if [[ -z "$user_input" ]]; then
    echo "Выбор не может быть пустым" >&2
    return 1
  fi

  if [[ "$user_input" =~ ^[0-9]+$ ]]; then
    local client_index=$((user_input - 1))

    if [[ $client_index -ge 0 ]] && [[ $client_index -lt ${#clients[@]} ]]; then
      selected_client="${clients[$client_index]}"
    else
      echo "Ошибка: неверный номер клиента" >&2
      return 1
    fi
  else
    local client_exists=false
    for client in "${clients[@]}"; do
      if [[ "$client" == "$user_input" ]]; then
        selected_client="$user_input"
        client_exists=true
        break
      fi
    done

    if [[ "$client_exists" == false ]]; then
      echo "Ошибка: клиент '$user_input' не найден" >&2
      return 1
    fi
  fi

  echo "$selected_client"
  return 0
}

create_client() {
  show_header
  echo "СОЗДАНИЕ КЛИЕНТА"
  echo ""
  read -p "Введите имя клиента: " client_name

  if [[ -z "$client_name" ]]; then
    echo "Имя клиента не может быть пустым"
    sleep 2
    return
  fi

  echo ""
  "$SCRIPT_DIR/vps-client-add.sh" "$client_name"
  echo ""
  read -p "Нажмите Enter для продолжения..."
}

remove_client() {
  show_header
  echo "УДАЛЕНИЕ КЛИЕНТА"
  echo ""

  if ! client_name=$(select_client); then
    echo ""
    read -p "Нажмите Enter для продолжения..."
    return
  fi

  echo ""
  read -p "Вы уверены, что хотите удалить клиента '$client_name'? (y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    "$SCRIPT_DIR/vps-client-remove.sh" "$client_name"
    echo ""
    read -p "Нажмите Enter для продолжения..."
  else
    echo "Отменено"
    sleep 1
  fi
}

rebuild_client_config() {
  show_header
  echo "ПЕРЕСОЗДАНИЕ КОНФИГУРАЦИИ КЛИЕНТА"
  echo ""

  if ! client_name=$(select_client); then
    echo ""
    read -p "Нажмите Enter для продолжения..."
    return
  fi

  echo ""
  echo "⚠ ВНИМАНИЕ: Это удалит старую конфигурацию и создаст новую!"
  echo "Это включает:"
  echo "  - Удаление WireGuard peer"
  echo "  - Удаление всех токенов и симлинков"
  echo "  - Создание новых ключей"
  echo "  - Пересоздание пакета"
  echo ""
  read -p "Продолжить? (y/n): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  echo ""
  echo "Удаление старой конфигурации..."
  "$SCRIPT_DIR/vps-client-remove.sh" "$client_name" || true

  echo ""
  echo "Создание новой конфигурации..."
  "$SCRIPT_DIR/vps-client-add.sh" "$client_name"

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

generate_package() {
  show_header
  echo "СБОРКА АРХИВА ДЛЯ КЛИЕНТА"
  echo ""

  if ! client_name=$(select_client); then
    echo ""
    read -p "Нажмите Enter для продолжения..."
    return
  fi

  echo ""
  echo "⚠ ВНИМАНИЕ: Пересоздание пакета НЕ удаляет старые токены!"
  echo "Старые токены будут продолжать работать со старым пакетом."
  echo ""
  read -p "Продолжить? (y/n): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Отменено"
    sleep 1
    return
  fi

  echo ""
  "$SCRIPT_DIR/vps-generate-package.sh" "$client_name"
  echo ""
  read -p "Нажмите Enter для продолжения..."
}

generate_install_link() {
  show_header
  echo "ГЕНЕРАЦИЯ ССЫЛКИ ДЛЯ УСТАНОВКИ"
  echo ""

  if ! client_name=$(select_client); then
    echo ""
    read -p "Нажмите Enter для продолжения..."
    return
  fi

  echo ""
  echo "ℹ INFO: Генерация новой ссылки удалит старые токены для этого клиента"
  echo ""
  read -p "Введите TTL токена в секундах (по умолчанию 86400): " ttl
  ttl=${ttl:-86400}

  echo ""
  "$SCRIPT_DIR/vps-generate-install-command.sh" "$client_name" "$ttl"
  echo ""
  read -p "Нажмите Enter для продолжения..."
}

show_clients_menu() {
  while true; do
    show_header
    echo "УПРАВЛЕНИЕ КЛИЕНТАМИ"
    echo ""
    echo "  1) Список клиентов"
    echo "  2) Создать клиента"
    echo "  3) Удалить клиента"
    echo "  4) Мониторинг клиентов"
    echo "  5) Пересоздать конфигурацию клиента"
    echo "  6) Собрать архив для клиента"
    echo "  7) Сгенерировать ссылку для установки"
    echo ""
    echo "  0) Назад"
    echo ""
    read -p "Выберите действие: " choice

    case $choice in
      1) show_clients_list ;;
      2) create_client ;;
      3) remove_client ;;
      4) monitor_clients ;;
      5) rebuild_client_config ;;
      6) generate_package ;;
      7) generate_install_link ;;
      0) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

show_server_info() {
  show_header
  echo "ПАРАМЕТРЫ СЕРВЕРА"
  echo ""

  if [[ -f "$PHOBOS_DIR/server/server.env" ]]; then
    cat "$PHOBOS_DIR/server/server.env"
  else
    echo "Файл конфигурации не найден"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

run_health_check() {
  show_header
  echo "ПРОВЕРКА СОСТОЯНИЯ СИСТЕМЫ"
  echo ""

  if [[ -f "$SCRIPT_DIR/vps-health-check.sh" ]]; then
    "$SCRIPT_DIR/vps-health-check.sh" || true
  else
    echo "Скрипт проверки не найден"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

monitor_clients() {
  show_header
  echo "МОНИТОРИНГ КЛИЕНТОВ"
  echo ""

  if [[ -f "$SCRIPT_DIR/vps-monitor-clients.sh" ]]; then
    "$SCRIPT_DIR/vps-monitor-clients.sh" || true
  else
    echo "Скрипт мониторинга не найден"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

cleanup_tokens() {
  show_header
  echo "ОЧИСТКА ПРОСРОЧЕННЫХ ТОКЕНОВ"
  echo ""

  if [[ -f "$SCRIPT_DIR/vps-cleanup-tokens.sh" ]]; then
    "$SCRIPT_DIR/vps-cleanup-tokens.sh" || true
  else
    echo "Скрипт очистки не найден"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

cleanup_orphaned_symlinks() {
  show_header
  echo "ОЧИСТКА ОСИРОТЕВШИХ СИМЛИНКОВ"
  echo ""

  if [[ -f "$SCRIPT_DIR/vps-cleanup-orphaned-symlinks.sh" ]]; then
    "$SCRIPT_DIR/vps-cleanup-orphaned-symlinks.sh" || true
  else
    echo "Скрипт очистки симлинков не найден"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

backup_configs() {
  show_header
  echo "РЕЗЕРВНОЕ КОПИРОВАНИЕ КОНФИГУРАЦИЙ"
  echo ""

  backup_dir="$PHOBOS_DIR/backups"
  backup_file="$backup_dir/phobos-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

  mkdir -p "$backup_dir"

  echo "Создание резервной копии..."
  tar -czf "$backup_file" \
    -C "$PHOBOS_DIR" \
    server/server.env \
    server/server_public.key \
    server/server_private.key \
    server/wg-obfuscator.conf \
    clients/ \
    2>/dev/null || true

  if [[ -f "$backup_file" ]]; then
    echo "Резервная копия создана: $backup_file"
    echo "Размер: $(du -h "$backup_file" | cut -f1)"
  else
    echo "Ошибка создания резервной копии"
  fi

  echo ""
  read -p "Нажмите Enter для продолжения..."
}

configure_obfuscator() {
  if [[ -f "$SCRIPT_DIR/vps-obfuscator-config.sh" ]]; then
    "$SCRIPT_DIR/vps-obfuscator-config.sh" || true
  else
    echo "Скрипт настройки obfuscator не найден"
    read -p "Нажмите Enter для продолжения..."
  fi
}

show_system_menu() {
  while true; do
    show_header
    echo "СИСТЕМНЫЕ ФУНКЦИИ"
    echo ""
    echo "  1) Показать параметры сервера"
    echo "  2) Проверка состояния системы"
    echo "  3) Очистка просроченных токенов"
    echo "  4) Очистка осиротевших симлинков"
    echo "  5) Резервное копирование конфигураций"
    echo ""
    echo "  0) Назад"
    echo ""
    read -p "Выберите действие: " choice

    case $choice in
      1) show_server_info ;;
      2) run_health_check ;;
      3) cleanup_tokens ;;
      4) cleanup_orphaned_symlinks ;;
      5) backup_configs ;;
      0) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

main_menu() {
  while true; do
    show_header
    echo "ГЛАВНОЕ МЕНЮ"
    echo ""
    echo "  1) Управление клиентами"
    echo "  2) Управление службами"
    echo "  3) Настройка WG-Obfuscator"
    echo "  4) Системные функции"
    echo ""
    echo "  0) Выход"
    echo ""
    read -p "Выберите раздел: " choice

    case $choice in
      1) show_clients_menu ;;
      2) show_services_menu ;;
      3) configure_obfuscator ;;
      4) show_system_menu ;;
      0) echo "Выход..."; exit 0 ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

main_menu
