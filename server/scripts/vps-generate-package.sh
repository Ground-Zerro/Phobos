#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CLIENT_ID="${1:-}"
PHOBOS_DIR="/opt/Phobos"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Этот скрипт требует root привилегии. Запустите: sudo $0 <client_id>"
  exit 1
fi

if [[ -z "$CLIENT_ID" ]]; then
  echo "Использование: $0 <client_id>"
  echo ""
  echo "Пример: $0 home-router"
  echo ""
  echo "Доступные клиенты:"
  ls -1 "$PHOBOS_DIR/clients" 2>/dev/null || echo "  (нет клиентов)"
  exit 1
fi

CLIENT_DIR="$PHOBOS_DIR/clients/$CLIENT_ID"

if [[ ! -d "$CLIENT_DIR" ]]; then
  echo "Ошибка: клиент $CLIENT_ID не найден."
  echo ""
  echo "Доступные клиенты:"
  ls -1 "$PHOBOS_DIR/clients" 2>/dev/null || echo "  (нет клиентов)"
  exit 1
fi

if [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-mipsel" ]] || \
   [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-mips" ]] || \
   [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-aarch64" ]]; then
  echo "Ошибка: бинарники wg-obfuscator для роутеров не найдены."
  echo "Сначала запустите vps-build-obfuscator.sh"
  exit 1
fi

echo "==> Создание установочного пакета для клиента $CLIENT_ID..."

TEMP_DIR=$(mktemp -d)
PACKAGE_DIR="$TEMP_DIR/phobos-$CLIENT_ID"

mkdir -p "$PACKAGE_DIR/bin"
mkdir -p "$PHOBOS_DIR/packages"

echo "==> Копирование файлов конфигурации..."

cp "$CLIENT_DIR/${CLIENT_ID}.conf" "$PACKAGE_DIR/${CLIENT_ID}.conf"
cp "$CLIENT_DIR/wg-obfuscator.conf" "$PACKAGE_DIR/wg-obfuscator.conf"

echo "==> Копирование бинарников для роутеров..."

cp "$PHOBOS_DIR/bin/wg-obfuscator-mipsel" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-mips" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-aarch64" "$PACKAGE_DIR/bin/"

echo "==> Копирование скрипта установки..."

TEMPLATE_FOUND=false

for TEMPLATE_PATH in \
  "$REPO_ROOT/client/templates/install-router.sh.template" \
  "/opt/Phobos/templates/install-router.sh.template" \
  "/root/client/templates/install-router.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/install-router.sh.template"; do

  if [[ -f "$TEMPLATE_PATH" ]]; then
    cp "$TEMPLATE_PATH" "$PACKAGE_DIR/install-router.sh"
    TEMPLATE_FOUND=true
    break
  fi
done

if [[ "$TEMPLATE_FOUND" == "false" ]]; then
  echo "Ошибка: шаблон install-router.sh не найден."
  echo "Проверьте наличие файла client/templates/install-router.sh.template"
  exit 1
fi

sed -i "s|{{CLIENT_NAME}}|${CLIENT_ID}|g" "$PACKAGE_DIR/install-router.sh"
chmod +x "$PACKAGE_DIR/install-router.sh"

echo "==> Копирование скрипта настройки WireGuard через RCI API..."

WG_CONFIG_FOUND=false

for WG_CONFIG_PATH in \
  "$REPO_ROOT/client/templates/router-configure-wireguard.sh.template" \
  "/opt/Phobos/templates/router-configure-wireguard.sh.template" \
  "/root/client/templates/router-configure-wireguard.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/router-configure-wireguard.sh.template"; do

  if [[ -f "$WG_CONFIG_PATH" ]]; then
    cp "$WG_CONFIG_PATH" "$PACKAGE_DIR/router-configure-wireguard.sh"
    chmod +x "$PACKAGE_DIR/router-configure-wireguard.sh"
    WG_CONFIG_FOUND=true
    break
  fi
done

if [[ "$WG_CONFIG_FOUND" == "false" ]]; then
  echo "Предупреждение: router-configure-wireguard.sh не найден - автоматическая настройка WireGuard будет недоступна"
fi

echo "==> Копирование скрипта проверки здоровья роутера..."

HEALTH_CHECK_FOUND=false

for HEALTH_CHECK_PATH in \
  "$REPO_ROOT/client/templates/router-health-check.sh.template" \
  "/opt/Phobos/templates/router-health-check.sh.template" \
  "/root/client/templates/router-health-check.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/router-health-check.sh.template"; do

  if [[ -f "$HEALTH_CHECK_PATH" ]]; then
    cp "$HEALTH_CHECK_PATH" "$PACKAGE_DIR/router-health-check.sh"
    chmod +x "$PACKAGE_DIR/router-health-check.sh"
    HEALTH_CHECK_FOUND=true
    break
  fi
done

if [[ "$HEALTH_CHECK_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон router-health-check.sh не найден (не критично)"
fi

echo "==> Копирование скрипта определения архитектуры..."

DETECT_ARCH_FOUND=false

for DETECT_ARCH_PATH in \
  "$REPO_ROOT/client/templates/detect-router-arch.sh.template" \
  "/opt/Phobos/templates/detect-router-arch.sh.template" \
  "/root/client/templates/detect-router-arch.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/detect-router-arch.sh.template"; do

  if [[ -f "$DETECT_ARCH_PATH" ]]; then
    cp "$DETECT_ARCH_PATH" "$PACKAGE_DIR/detect-router-arch.sh"
    chmod +x "$PACKAGE_DIR/detect-router-arch.sh"
    DETECT_ARCH_FOUND=true
    break
  fi
done

if [[ "$DETECT_ARCH_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон detect-router-arch.sh не найден (не критично)"
fi

echo "==> Копирование скрипта удаления Phobos..."

UNINSTALL_FOUND=false

for UNINSTALL_PATH in \
  "$REPO_ROOT/client/templates/router-uninstall.sh.template" \
  "/opt/Phobos/templates/router-uninstall.sh.template" \
  "/root/client/templates/router-uninstall.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/router-uninstall.sh.template"; do

  if [[ -f "$UNINSTALL_PATH" ]]; then
    cp "$UNINSTALL_PATH" "$PACKAGE_DIR/router-uninstall.sh"
    chmod +x "$PACKAGE_DIR/router-uninstall.sh"
    UNINSTALL_FOUND=true
    break
  fi
done

if [[ "$UNINSTALL_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон router-uninstall.sh не найден (не критично)"
fi

echo "==> Создание README..."

if [[ ! -f "$PHOBOS_DIR/server/server.env" ]]; then
  echo "Ошибка: файл $PHOBOS_DIR/server/server.env не найден"
  echo "Сначала запустите vps-init-all.sh для инициализации сервера"
  exit 1
fi

set +e
source "$PHOBOS_DIR/server/server.env" 2>/dev/null
SOURCE_RESULT=$?
set -e

if [[ $SOURCE_RESULT -ne 0 ]]; then
  echo "Ошибка: файл server.env содержит некорректные данные"
  echo "Повторно запустите vps-init-all.sh для пересоздания конфигурации"
  exit 1
fi

cat > "$PACKAGE_DIR/README.txt" <<EOF
====================================================
  Установочный пакет Phobos для Keenetic
  Клиент: $CLIENT_ID
  Дата: $(date)
====================================================

ЦЕЛЕВАЯ ПЛАТФОРМА:
  Роутер Keenetic с установленным Entware

ИНСТРУКЦИЯ ПО УСТАНОВКЕ:

Шаг 1. Загрузите архив на роутер
---------------------------------------
  scp phobos-$CLIENT_ID.tar.gz root@<router_ip>:/tmp/

Шаг 2. Подключитесь к роутеру через SSH
---------------------------------------
  ssh root@<router_ip>

Шаг 3. Распакуйте и запустите установку
---------------------------------------
  cd /tmp
  tar xzf phobos-$CLIENT_ID.tar.gz
  cd phobos-$CLIENT_ID

  ОПЦИОНАЛЬНО: Определите архитектуру роутера
  chmod +x detect-router-arch.sh
  ./detect-router-arch.sh

  Запустите установку:
  chmod +x install-router.sh
  ./install-router.sh

  Скрипт автоматически:
  ✓ Установит wg-obfuscator (WireGuard встроен в прошивку!)
  ✓ Настроит WireGuard через RCI API (автоматически!)
  ✓ Создаст интерфейс с именем "Phobos-$CLIENT_ID"
  ✓ Активирует подключение

Шаг 4. Проверка результата
---------------------------------------
  Если автоматическая настройка прошла успешно:
    ✓ WireGuard интерфейс создан и активен
    ✓ Handshake установлен
    ✓ Готово к использованию!

  Если RCI API недоступен (старая версия Keenetic OS):
    ⚠ Требуется ручной импорт WireGuard конфигурации:

    1. Откройте веб-панель Keenetic (http://192.168.1.1 или http://my.keenetic.net)
    2. Перейдите: Интернет → WireGuard
    3. Нажмите "Добавить подключение"
    4. Выберите "Импортировать из файла"
    5. Укажите файл: /opt/etc/Phobos/$CLIENT_ID.conf
    6. Активируйте подключение

    Просмотр содержимого конфига:
      cat /opt/etc/Phobos/$CLIENT_ID.conf

Шаг 5. Проверка соединения
---------------------------------------
  ./router-health-check.sh   
  ps | grep wg-obfuscator    
  ping 10.8.0.1              

ПАРАМЕТРЫ СЕРВЕРА:

  Публичный IP VPS (IPv4): ${SERVER_PUBLIC_IP_V4:-$SERVER_PUBLIC_IP}
$(if [[ -n "${SERVER_PUBLIC_IP_V6:-}" ]]; then echo "  Публичный IP VPS (IPv6): $SERVER_PUBLIC_IP_V6"; fi)
  Порт obfuscator: $OBFUSCATOR_PORT/udp (только IPv4)
  Endpoint в WireGuard: 127.0.0.1:13255 (локальный obfuscator)

АРХИТЕКТУРА:

  - Obfuscator работает ТОЛЬКО по IPv4 (максимальная совместимость)
  - WireGuard поддерживает dual-stack (IPv4 + IPv6)
$(if [[ -n "${SERVER_PUBLIC_IP_V6:-}" ]]; then
echo "  - На этом сервере IPv6 включен, конфиг WireGuard содержит оба адреса"
else
echo "  - На этом сервере IPv6 не настроен (только IPv4)"
fi)

СОДЕРЖИМОЕ АРХИВА:

  - $CLIENT_ID.conf                - Конфиг WireGuard (dual-stack если IPv6 доступен)
  - wg-obfuscator.conf             - Конфиг obfuscator (только IPv4)
  - install-router.sh              - Скрипт установки (obfuscator + WireGuard RCI)
  - router-configure-wireguard.sh  - Скрипт автоматической настройки WireGuard через RCI API
  - router-health-check.sh         - Скрипт проверки состояния роутера
  - router-uninstall.sh            - Скрипт удаления Phobos с роутера
  - detect-router-arch.sh          - Скрипт определения архитектуры роутера
  - bin/wg-obfuscator-*            - Бинарники для разных архитектур
    - wg-obfuscator-mipsel           (MIPS Little Endian)
    - wg-obfuscator-mips             (MIPS Big Endian)
    - wg-obfuscator-aarch64          (ARM64)
  - README.txt                     - Этот файл

УСТАНОВЛЕННЫЕ ФАЙЛЫ НА РОУТЕРЕ:

  /opt/bin/wg-obfuscator                      - Бинарник obfuscator
  /opt/etc/Phobos/wg-obfuscator.conf          - Конфиг obfuscator
  /opt/etc/Phobos/$CLIENT_ID.conf             - Конфиг WireGuard (fallback)
  /opt/etc/init.d/S49wg-obfuscator            - Init-скрипт obfuscator

ВАЖНЫЕ ЗАМЕЧАНИЯ:

  - WireGuard встроен в прошивку Keenetic - установка не требуется
  - НОВОЕ: WireGuard настраивается АВТОМАТИЧЕСКИ через RCI API (Keenetic OS 4.0+)
  - Создаётся интерфейс с description="Phobos-$CLIENT_ID" для идентификации
  - Fallback конфиг сохраняется для ручного импорта при необходимости
  - Obfuscator управляется через init-скрипт
  - Endpoint в конфиге указывает на локальный obfuscator (127.0.0.1:13255)
  - При обновлении конфигурации существующий интерфейс обновится автоматически

УДАЛЕНИЕ PHOBOS:

  Для удаления Phobos с роутера выполните:
  1. cd /tmp/phobos-$CLIENT_ID
  2. chmod +x router-uninstall.sh
  3. ./router-uninstall.sh

  Скрипт автоматически:
  ✓ Остановит wg-obfuscator
  ✓ Удалит все WireGuard интерфейсы Phobos
  ✓ Удалит бинарник и конфигурационные файлы
  ✓ Удалит init-скрипт

ОТЛАДКА:

  Если возникли проблемы, проверьте:
  1. ps | grep wg-obfuscator     
  2. /opt/etc/init.d/S49wg-obfuscator start  
  3. В веб-панели Keenetic проверьте статус WireGuard

ПОДДЕРЖКА:

  GitHub: https://github.com/yourusername/Phobos

====================================================
EOF

echo "==> Упаковка архива..."

cd "$TEMP_DIR"
tar czf "phobos-$CLIENT_ID.tar.gz" "phobos-$CLIENT_ID"

mv "phobos-$CLIENT_ID.tar.gz" "$PHOBOS_DIR/packages/"

cd /
rm -rf "$TEMP_DIR"

PACKAGE_PATH="$PHOBOS_DIR/packages/phobos-$CLIENT_ID.tar.gz"
PACKAGE_SIZE=$(du -h "$PACKAGE_PATH" | cut -f1)

echo ""
echo "==> Установочный пакет успешно создан!"
echo ""
echo "Путь к пакету: $PACKAGE_PATH"
echo "Размер: $PACKAGE_SIZE"
echo ""
echo "Содержимое архива:"
tar tzf "$PACKAGE_PATH"
echo ""
