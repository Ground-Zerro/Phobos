#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

cd /tmp 2>/dev/null || cd / 2>/dev/null || true

PHOBOS_DIR="/opt/Phobos"
WWW_DIR="$PHOBOS_DIR/www"
TOKENS_FILE="$PHOBOS_DIR/tokens/tokens.json"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0"
  exit 1
fi

echo "=========================================="
echo "  Очистка осиротевших симлинков"
echo "=========================================="
echo ""

CLEANED_SYMLINKS=0
CLEANED_INIT_SCRIPTS=0
CLEANED_TOKEN_DIRS=0

ACTIVE_CLIENTS=()
if [[ -d "$PHOBOS_DIR/clients" ]]; then
  for client_dir in "$PHOBOS_DIR/clients"/*; do
    if [[ -d "$client_dir" ]]; then
      ACTIVE_CLIENTS+=("$(basename "$client_dir")")
    fi
  done
fi

echo "==> Активные клиенты: ${#ACTIVE_CLIENTS[@]}"
for client in "${ACTIVE_CLIENTS[@]}"; do
  echo "  - $client"
done
echo ""

VALID_TOKENS=()
if [[ -f "$TOKENS_FILE" ]] && [[ -s "$TOKENS_FILE" ]] && jq empty "$TOKENS_FILE" 2>/dev/null; then
  while IFS= read -r token; do
    [[ -n "$token" ]] && VALID_TOKENS+=("$token")
  done < <(jq -r '.[].token' "$TOKENS_FILE" 2>/dev/null || echo "")
fi

echo "==> Валидные токены: ${#VALID_TOKENS[@]}"
echo ""

client_exists() {
  local client_id="$1"
  for active in "${ACTIVE_CLIENTS[@]}"; do
    if [[ "$active" == "$client_id" ]]; then
      return 0
    fi
  done
  return 1
}

token_is_valid() {
  local token="$1"
  for valid in "${VALID_TOKENS[@]}"; do
    if [[ "$valid" == "$token" ]]; then
      return 0
    fi
  done
  return 1
}

echo "==> Проверка директорий с токенами..."
if [[ -d "$WWW_DIR/packages" ]]; then
  for token_dir in "$WWW_DIR/packages"/*; do
    if [[ ! -d "$token_dir" ]]; then
      continue
    fi

    TOKEN=$(basename "$token_dir")
    
    if ! token_is_valid "$TOKEN"; then
      echo "Найдена директория с невалидным токеном: $TOKEN"
      
      for symlink in "$token_dir"/*; do
        if [[ -L "$symlink" ]]; then
          echo "  - Симлинк: $(basename "$symlink")"
          ((CLEANED_SYMLINKS++))
        fi
      done
      
      rm -rf "$token_dir"
      echo "  ✓ Директория удалена"
      ((CLEANED_TOKEN_DIRS++))
      echo ""
      continue
    fi

    for symlink in "$token_dir"/*; do
      if [[ -L "$symlink" ]]; then
        if [[ ! -e "$symlink" ]]; then
          echo "Найден битый симлинк: $symlink"
          rm -f "$symlink"
          echo "  ✓ Удален"
          ((CLEANED_SYMLINKS++))
        else
          SYMLINK_NAME=$(basename "$symlink")
          if [[ "$SYMLINK_NAME" =~ phobos-(.+)\.tar\.gz ]]; then
            CLIENT_ID="${BASH_REMATCH[1]}"
            if ! client_exists "$CLIENT_ID"; then
              echo "Найден симлинк на удаленного клиента: $CLIENT_ID"
              rm -f "$symlink"
              echo "  ✓ Удален"
              ((CLEANED_SYMLINKS++))
            fi
          fi
        fi
      fi
    done

    if [[ -z "$(ls -A "$token_dir" 2>/dev/null)" ]]; then
      echo "Удаление пустой директории: $TOKEN"
      rm -rf "$token_dir"
      ((CLEANED_TOKEN_DIRS++))
    fi
  done
fi

echo ""
echo "==> Проверка init-скриптов..."
if [[ -d "$WWW_DIR/init" ]]; then
  for init_script in "$WWW_DIR/init"/*.sh; do
    if [[ ! -f "$init_script" ]]; then
      continue
    fi

    SCRIPT_NAME=$(basename "$init_script" .sh)
    
    if ! token_is_valid "$SCRIPT_NAME"; then
      echo "Найден init-скрипт с невалидным токеном: $SCRIPT_NAME"
      rm -f "$init_script"
      echo "  ✓ Удален"
      ((CLEANED_INIT_SCRIPTS++))
    fi
  done
fi

echo ""
echo "=========================================="
echo "  Очистка завершена!"
echo "=========================================="
echo ""
echo "Статистика:"
echo "  Удалено симлинков: $CLEANED_SYMLINKS"
echo "  Удалено init-скриптов: $CLEANED_INIT_SCRIPTS"
echo "  Удалено директорий токенов: $CLEANED_TOKEN_DIRS"
echo ""

if [[ $CLEANED_SYMLINKS -eq 0 ]] && [[ $CLEANED_INIT_SCRIPTS -eq 0 ]] && [[ $CLEANED_TOKEN_DIRS -eq 0 ]]; then
  echo "✓ Система чистая, осиротевших файлов не найдено"
else
  echo "✓ Система очищена от осиротевших файлов"
fi
echo ""
