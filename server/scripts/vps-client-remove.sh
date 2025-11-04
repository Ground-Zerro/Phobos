#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLIENT_NAME="${1:-}"
PHOBOS_DIR="/opt/Phobos"
WG_CONFIG="/etc/wireguard/wg0.conf"
SERVER_ENV="$PHOBOS_DIR/server/server.env"
TOKENS_FILE="$PHOBOS_DIR/tokens/tokens.json"
WWW_DIR="$PHOBOS_DIR/www"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0 <client_name>"
  exit 1
fi

if [[ -z "$CLIENT_NAME" ]]; then
  echo "Использование: $0 <client_name>"
  echo ""
  echo "Пример: $0 home-router"
  exit 1
fi

CLIENT_ID=$(echo "$CLIENT_NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
CLIENT_DIR="$PHOBOS_DIR/clients/$CLIENT_ID"

if [[ ! -d "$CLIENT_DIR" ]]; then
  echo "Ошибка: клиент $CLIENT_ID не найден."
  exit 1
fi

echo "=========================================="
echo "  Удаление клиента: $CLIENT_NAME"
echo "=========================================="
echo ""

if [[ -f "$CLIENT_DIR/client_public.key" ]]; then
  CLIENT_PUBLIC_KEY=$(cat "$CLIENT_DIR/client_public.key")

  echo "==> Удаление peer из WireGuard конфигурации..."
  echo "Поиск peer с публичным ключом: $CLIENT_PUBLIC_KEY"

  if grep -q "$CLIENT_PUBLIC_KEY" "$WG_CONFIG"; then
    echo "Peer найден в конфигурации, выполняется удаление..."
    awk -v pubkey="$CLIENT_PUBLIC_KEY" '
      BEGIN { in_peer = 0; skip_peer = 0; buffer = "" }

      /^\[Peer\]$/ {
        if (in_peer && !skip_peer && buffer != "") {
          print "[Peer]"
          print buffer
        }
        in_peer = 1
        skip_peer = 0
        buffer = ""
        next
      }

      /^\[/ && !/^\[Peer\]$/ {
        if (in_peer && !skip_peer && buffer != "") {
          print "[Peer]"
          print buffer
        }
        in_peer = 0
        skip_peer = 0
        buffer = ""
        print
        next
      }

      in_peer {
        line_clean = $0
        gsub(/^[ \t]+/, "", line_clean)
        gsub(/[ \t]+$/, "", line_clean)
        split(line_clean, fields, " ")
        if (fields[1] == "PublicKey" && fields[2] == "=" && fields[3] == pubkey) {
          skip_peer = 1
        }
        if (buffer != "") buffer = buffer "\n"
        buffer = buffer $0
        next
      }

      !in_peer { print }

      END {
        if (in_peer && !skip_peer && buffer != "") {
          print "[Peer]"
          print buffer
        }
      }
    ' "$WG_CONFIG" > "$WG_CONFIG.tmp" && mv "$WG_CONFIG.tmp" "$WG_CONFIG"

    if ! grep -q "$CLIENT_PUBLIC_KEY" "$WG_CONFIG"; then
      echo "Peer удален из $WG_CONFIG"
      echo "==> Применение конфигурации WireGuard..."
      wg syncconf wg0 <(wg-quick strip wg0)
    else
      echo "ОШИБКА: Не удалось удалить peer из $WG_CONFIG"
      echo "Публичный ключ: $CLIENT_PUBLIC_KEY"
      return 1
    fi
  else
    echo "Peer не найден в конфигурации WireGuard (возможно уже удален)"
  fi
else
  echo "⚠ Публичный ключ клиента не найден, пропуск удаления из WireGuard"
fi

echo "==> Удаление директории клиента..."
rm -rf "$CLIENT_DIR"
echo "Директория $CLIENT_DIR удалена"

echo "==> Удаление пакета..."
PACKAGE_FILE="$PHOBOS_DIR/packages/phobos-$CLIENT_ID.tar.gz"
if [[ -f "$PACKAGE_FILE" ]]; then
  rm -f "$PACKAGE_FILE"
  echo "Пакет $PACKAGE_FILE удален"
else
  echo "Пакет не найден (возможно не был создан)"
fi

echo "==> Очистка токенов и связанных файлов..."
if [[ -f "$TOKENS_FILE" ]]; then
  if command -v jq >/dev/null 2>&1; then
    if [[ ! -s "$TOKENS_FILE" ]]; then
      echo "[]" > "$TOKENS_FILE"
      chmod 600 "$TOKENS_FILE"
    elif ! jq empty "$TOKENS_FILE" 2>/dev/null; then
      echo "⚠ tokens.json поврежден, создаем резервную копию"
      cp "$TOKENS_FILE" "$TOKENS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
      echo "[]" > "$TOKENS_FILE"
      chmod 600 "$TOKENS_FILE"
    fi

    TOKENS_TO_REMOVE=$(jq -r ".[] | select(.client == \"$CLIENT_ID\") | .token" "$TOKENS_FILE" 2>/dev/null || echo "")

    if [[ -n "$TOKENS_TO_REMOVE" ]]; then
      while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        echo "Удаление токена: $token"

        if [[ -f "$WWW_DIR/init/${token}.sh" ]]; then
          rm -f "$WWW_DIR/init/${token}.sh"
          echo "  ✓ Удален init-скрипт"
        fi

        if [[ -d "$WWW_DIR/packages/${token}" ]]; then
          rm -rf "$WWW_DIR/packages/${token}"
          echo "  ✓ Удалена директория с симлинками"
        fi
      done <<< "$TOKENS_TO_REMOVE"

      TEMP_FILE=$(mktemp)
      jq "map(select(.client != \"$CLIENT_ID\"))" "$TOKENS_FILE" > "$TEMP_FILE"
      if jq empty "$TEMP_FILE" 2>/dev/null; then
        mv "$TEMP_FILE" "$TOKENS_FILE"
        chmod 600 "$TOKENS_FILE"
        echo "Токены клиента удалены из базы данных"
      else
        echo "⚠ Ошибка обновления tokens.json"
        rm -f "$TEMP_FILE"
      fi
    else
      echo "Токены для клиента не найдены"
    fi
  else
    echo "⚠ jq не установлен, пропуск очистки tokens.json"
  fi
else
  echo "Файл tokens.json не найден"
fi

echo "==> Дополнительная очистка: поиск осиротевших симлинков..."
CLEANED_ORPHANS=0
if [[ -d "$WWW_DIR/packages" ]]; then
  for token_dir in "$WWW_DIR/packages"/*; do
    if [[ -d "$token_dir" ]]; then
      if [[ -L "$token_dir/phobos-$CLIENT_ID.tar.gz" ]]; then
        echo "Найден осиротевший симлинк в: $(basename "$token_dir")"
        rm -rf "$token_dir"
        echo "  ✓ Удален"
        ((CLEANED_ORPHANS++))
      fi
    fi
  done
fi

if [[ $CLEANED_ORPHANS -gt 0 ]]; then
  echo "Удалено осиротевших симлинков: $CLEANED_ORPHANS"
else
  echo "Осиротевших симлинков не найдено"
fi

echo ""
echo "=========================================="
echo "  Клиент $CLIENT_NAME успешно удален!"
echo "=========================================="
echo ""
echo "Удалено:"
echo "  ✓ Конфигурация WireGuard peer"
echo "  ✓ Директория клиента: $CLIENT_DIR"
echo "  ✓ Пакет: phobos-$CLIENT_ID.tar.gz"
echo "  ✓ Все токены и связанные файлы"
echo "  ✓ Осиротевшие симлинки: $CLEANED_ORPHANS"
echo ""
