#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib-core.sh"

check_root
load_env
ensure_dirs

CMD="${1:-status}"

action_status() {
  log_info "Проверка состояния системы..."
  
  # Services
  local errors=0
  for svc in wg-quick@wg0 wg-obfuscator phobos-http; do
     if systemctl is-active --quiet "$svc"; then
        log_success "Служба $svc активна"
     else
        log_error "Служба $svc ОСТАНОВЛЕНА"
        ((errors++))
     fi
  done
  
  # Ports
  if ss -ulpn | grep -q ":$OBFUSCATOR_PORT "; then
     log_success "Порт Obfuscator ($OBFUSCATOR_PORT/udp) прослушивается"
  else
     log_error "Порт Obfuscator НЕ доступен"
     ((errors++))
  fi
  
  # Disk
  local free_mb=$(df -m / | awk 'NR==2 {print $4}')
  if [[ "$free_mb" -lt 500 ]]; then
     log_warn "Мало места на диске: ${free_mb}MB"
  else
     log_success "Свободное место: ${free_mb}MB"
  fi
  
  if [[ "$errors" -eq 0 ]]; then
     echo "Система работает нормально."
  else
     echo "Обнаружены проблемы ($errors)."
     exit 1
  fi
}

action_cleanup() {
  log_info "Очистка системы..."
  local now=$(date +%s)
  
  # 1. Tokens
  if [[ -f "$TOKENS_FILE" ]] && command -v jq >/dev/null; then
     local expired=$(jq -r ".[] | select(.expires < $now) | .token" "$TOKENS_FILE")
     for t in $expired; do
        log_info "Удаление просроченного токена: $t"
        rm -f "$WWW_DIR/init/$t.sh"
        rm -rf "$WWW_DIR/packages/$t"
     done
     # Update JSON
     jq "[.[] | select(.expires >= $now)]" "$TOKENS_FILE" > "$TOKENS_FILE.tmp" && mv "$TOKENS_FILE.tmp" "$TOKENS_FILE"
  fi
  
  if [[ -d "$WWW_DIR/packages" ]]; then
     for d in "$WWW_DIR/packages"/*; do
        if [[ -d "$d" ]]; then
           local t=$(basename "$d")
           local in_json=false
           if [[ -f "$TOKENS_FILE" ]]; then
              in_json=$(jq -r --arg t "$t" 'map(select(.token == $t)) | length > 0' "$TOKENS_FILE" 2>/dev/null || echo false)
           fi
           if [[ "$in_json" == "false" ]]; then
              log_warn "Найден осиротевший каталог: $t"
              rm -rf "$d"
              rm -f "$WWW_DIR/init/$t.sh"
           fi
        fi
     done
  fi
  
  log_success "Очистка завершена."
}

action_monitor() {
  echo "Мониторинг клиентов (Live)..."
  echo "Ctrl+C для выхода"
  watch -n 2 "wg show wg0; echo ''; echo '--- Connections ---'; ss -un state established '( dport = :$OBFUSCATOR_PORT )'"
}

case "$CMD" in
  status|health) action_status ;;
  cleanup) action_cleanup ;;
  monitor) action_monitor ;;
  *)
    echo "Usage: $0 {status|cleanup|monitor}"
    exit 1
    ;;
esac
