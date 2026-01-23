#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

PHOBOS_DIR="/opt/Phobos"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CLIENT_SCRIPT="$SCRIPT_DIR/phobos-client.sh"
SYSTEM_SCRIPT="$SCRIPT_DIR/phobos-system.sh"
CONFIG_SCRIPT="$SCRIPT_DIR/vps-obfuscator-config.sh"

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

# Helper: Select Client
select_client() {
  local clients=()
  local i=1
  
  if [[ ! -d "$PHOBOS_DIR/clients" ]] || [[ -z "$(ls -A "$PHOBOS_DIR/clients" 2>/dev/null)" ]]; then
    echo "Нет созданных клиентов" >&2
    return 1
  fi
  
  echo "ДОСТУПНЫЕ КЛИЕНТЫ:" >&2
  printf "% -4s % -20s\n" "№" "CLIENT ID" >&2
  echo "------------------------" >&2
  
  for d in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$d" ]]; then
       local id=$(basename "$d")
       clients+=("$id")
       printf "% -4s % -20s\n" "$i" "$id" >&2
       ((i++))
    fi
  done
  echo "" >&2
  
  read -p "Введите номер или имя: " input
  if [[ -z "$input" ]]; then return 1; fi
  
  if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= ${#clients[@]})); then
     echo "${clients[$((input-1))]}"
     return 0
  fi
  
  # Check if name matches
  for c in "${clients[@]}"; do
    if [[ "$c" == "$input" ]]; then
       echo "$c"
       return 0
    fi
  done
  
  echo "Клиент не найден" >&2
  return 1
}

# Services Menu
show_services_menu() {
  while true; do
    show_header
    echo "УПРАВЛЕНИЕ СЛУЖБАМИ"
    echo ""
    
    local wg_st="STOPPED"
    systemctl is-active --quiet wg-quick@wg0 && wg_st="RUNNING"
    local obf_st="STOPPED"
    systemctl is-active --quiet wg-obfuscator && obf_st="RUNNING"
    local http_st="STOPPED"
    systemctl is-active --quiet phobos-http && http_st="RUNNING"
    
    echo "  1) WireGuard    [$wg_st] - Запуск/Рестарт"
    echo "  2) WireGuard    - Стоп"
    echo "  3) WireGuard    - Логи"
    echo ""
    echo "  4) Obfuscator   [$obf_st] - Запуск/Рестарт"
    echo "  5) Obfuscator   - Стоп"
    echo "  6) Obfuscator   - Логи"
    echo ""
    echo "  7) HTTP Server  [$http_st] - Запуск/Рестарт"
    echo "  8) HTTP Server  - Стоп"
    echo "  9) HTTP Server  - Логи"
    echo ""
    echo " 10) РЕСТАРТ ВСЕГО"
    echo " 11) СТОП ВСЕГО"
    echo ""
    echo "  0) Назад"
    read -p "Выбор: " choice
    
    case $choice in
      1) systemctl restart wg-quick@wg0; sleep 1 ;; 
      2) systemctl stop wg-quick@wg0; sleep 1 ;; 
      3) journalctl -u wg-quick@wg0 -n 20 --no-pager; read -p "Enter..." ;; 
      4) systemctl restart wg-obfuscator; sleep 1 ;; 
      5) systemctl stop wg-obfuscator; sleep 1 ;; 
      6) journalctl -u wg-obfuscator -n 20 --no-pager; read -p "Enter..." ;; 
      7) systemctl restart phobos-http; sleep 1 ;; 
      8) systemctl stop phobos-http; sleep 1 ;; 
      9) journalctl -u phobos-http -n 20 --no-pager; read -p "Enter..." ;; 
      10) systemctl restart wg-quick@wg0 wg-obfuscator phobos-http; echo "Перезапущено."; sleep 2 ;; 
      11) systemctl stop wg-quick@wg0 wg-obfuscator phobos-http; echo "Остановлено."; sleep 2 ;; 
      0) break ;; 
    esac
  done
}

show_clients_menu() {
  while true; do
    show_header
    echo "УПРАВЛЕНИЕ КЛИЕНТАМИ"
    echo ""
    echo "  1) Список клиентов"
    echo "  2) Создать клиента"
    echo "  3) Удалить клиента"
    echo "  4) Мониторинг (Live)"
    echo "  5) Пересоздать клиента"
    echo "  6) Ссылка на установку"
    echo ""
    echo "  0) Назад"
    read -p "Выбор: " choice

    case $choice in
      1)
        show_header
        "$CLIENT_SCRIPT" list
        echo ""
        read -p "Enter..."
        ;;
      2)
        show_header
        read -p "Имя клиента: " name
        [[ -n "$name" ]] && "$CLIENT_SCRIPT" add "$name"
        read -p "Enter..."
        ;;
      3)
        show_header
        if client=$(select_client); then
           read -p "Удалить $client? [y/N]: " ans
           [[ "$ans" =~ ^[Yy] ]] && "$CLIENT_SCRIPT" remove "$client"
        fi
        read -p "Enter..."
        ;;
      4) "$SYSTEM_SCRIPT" monitor ;;
      5)
        show_header
        if client=$(select_client); then
           read -p "Пересоздать $client? [y/N]: " ans
           if [[ "$ans" =~ ^[Yy] ]]; then
             "$CLIENT_SCRIPT" rebuild "$client"
             "$CLIENT_SCRIPT" package "$client"
           fi
        fi
        read -p "Enter..."
        ;;
      6)
        show_header
        if client=$(select_client); then
           echo ""
           if check_result=$("$CLIENT_SCRIPT" check "$client" 2>&1); then
             read -p "TTL (сек) [86400]: " ttl
             "$CLIENT_SCRIPT" link "$client" "${ttl:-86400}"
           else
             echo ""
             echo "$check_result"
             echo ""
             read -p "Пересоздать клиента с новыми параметрами? [y/N]: " ans
             if [[ "$ans" =~ ^[Yy] ]]; then
               "$CLIENT_SCRIPT" rebuild "$client"
               "$CLIENT_SCRIPT" package "$client"
               read -p "TTL (сек) [86400]: " ttl
               "$CLIENT_SCRIPT" link "$client" "${ttl:-86400}"
             fi
           fi
        fi
        read -p "Enter..."
        ;;
      0) break ;;
    esac
  done
}

# System Menu
show_system_menu() {
  while true; do
    show_header
    echo "СИСТЕМНЫЕ ФУНКЦИИ"
    echo ""
    echo "  1) Health Check"
    echo "  2) Очистка (токены, мусор)"
    echo "  3) Показать конфиг (env)"
    echo ""
    echo "  0) Назад"
    read -p "Выбор: " choice

    case $choice in
      1) "$SYSTEM_SCRIPT" status; read -p "Enter..." ;;
      2) "$SYSTEM_SCRIPT" cleanup; read -p "Enter..." ;;
      3) cat "$PHOBOS_DIR/server/server.env"; echo ""; read -p "Enter..." ;;
      0) break ;;
    esac
  done
}

# Main
while true; do
  show_header
  echo "ГЛАВНОЕ МЕНЮ"
  echo ""
  echo "  1) Управление клиентами"
  echo "  2) Управление службами"
  echo "  3) Настройка Obfuscator"
  echo "  4) Системные функции"
  echo ""
  echo "  0) Выход"
  echo ""
  read -p "Ваш выбор: " choice
  
  case $choice in
    1) show_clients_menu ;; 
    2) show_services_menu ;; 
    3) "$CONFIG_SCRIPT" ;; 
    4) show_system_menu ;; 
    0) exit 0 ;; 
    *) echo "Неверный выбор"; sleep 1 ;; 
  esac
done