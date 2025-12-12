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
   [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-aarch64" ]] || \
   [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-armv7" ]] || \
   [[ ! -f "$PHOBOS_DIR/bin/wg-obfuscator-x86_64" ]]; then
  echo "Ошибка: бинарники wg-obfuscator не найдены."
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

echo "==> Копирование бинарников для роутеров и клиентов..."

cp "$PHOBOS_DIR/bin/wg-obfuscator-mipsel" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-mips" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-aarch64" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-armv7" "$PACKAGE_DIR/bin/"
cp "$PHOBOS_DIR/bin/wg-obfuscator-x86_64" "$PACKAGE_DIR/bin/"

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

echo "==> Копирование скрипта настройки WireGuard через RCI API (Keenetic)..."

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
  echo "Предупреждение: router-configure-wireguard.sh не найден - автоматическая настройка WireGuard на Keenetic будет недоступна"
fi

echo "==> Копирование скрипта настройки WireGuard через UCI (OpenWRT)..."

WG_CONFIG_OPENWRT_FOUND=false

for WG_CONFIG_OPENWRT_PATH in \
  "$REPO_ROOT/client/templates/router-configure-wireguard-openwrt.sh.template" \
  "/opt/Phobos/templates/router-configure-wireguard-openwrt.sh.template" \
  "/root/client/templates/router-configure-wireguard-openwrt.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/router-configure-wireguard-openwrt.sh.template"; do

  if [[ -f "$WG_CONFIG_OPENWRT_PATH" ]]; then
    cp "$WG_CONFIG_OPENWRT_PATH" "$PACKAGE_DIR/router-configure-wireguard-openwrt.sh"
    chmod +x "$PACKAGE_DIR/router-configure-wireguard-openwrt.sh"
    WG_CONFIG_OPENWRT_FOUND=true
    break
  fi
done

if [[ "$WG_CONFIG_OPENWRT_FOUND" == "false" ]]; then
  echo "Предупреждение: router-configure-wireguard-openwrt.sh не найден - автоматическая настройка WireGuard на OpenWRT будет недоступна"
fi

echo "==> Копирование скрипта проверки здоровья роутера..."

HEALTH_CHECK_FOUND=false

for HEALTH_CHECK_PATH in \
  "$REPO_ROOT/client/templates/health-check.sh.template" \
  "/opt/Phobos/templates/health-check.sh.template" \
  "/root/client/templates/health-check.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/health-check.sh.template"; do

  if [[ -f "$HEALTH_CHECK_PATH" ]]; then
    cp "$HEALTH_CHECK_PATH" "$PACKAGE_DIR/health-check.sh"
    chmod +x "$PACKAGE_DIR/health-check.sh"
    HEALTH_CHECK_FOUND=true
    break
  fi
done

if [[ "$HEALTH_CHECK_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон health-check.sh не найден (не критично)"
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
  "$REPO_ROOT/client/templates/phobos-uninstall.sh.template" \
  "/opt/Phobos/templates/phobos-uninstall.sh.template" \
  "/root/client/templates/phobos-uninstall.sh.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/phobos-uninstall.sh.template"; do

  if [[ -f "$UNINSTALL_PATH" ]]; then
    cp "$UNINSTALL_PATH" "$PACKAGE_DIR/phobos-uninstall.sh"
    chmod +x "$PACKAGE_DIR/phobos-uninstall.sh"
    UNINSTALL_FOUND=true
    break
  fi
done

if [[ "$UNINSTALL_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон phobos-uninstall.sh не найден (не критично)"
fi

echo "==> Копирование скрипта интеграции 3x-ui..."

XUITOOL_FOUND=false

for XUITOOL_PATH in \
  "$REPO_ROOT/client/templates/3xui.py.template" \
  "/opt/Phobos/templates/3xui.py.template" \
  "/root/client/templates/3xui.py.template" \
  "$(dirname "$SCRIPT_DIR")/client/templates/3xui.py.template"; do

  if [[ -f "$XUITOOL_PATH" ]]; then
    cp "$XUITOOL_PATH" "$PACKAGE_DIR/3xui.py"
    chmod +x "$PACKAGE_DIR/3xui.py"
    XUITOOL_FOUND=true
    break
  fi
done

if [[ "$XUITOOL_FOUND" == "false" ]]; then
  echo "Предупреждение: шаблон 3xui.py не найден (не критично для стандартных установок)"
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
  Установочный пакет Phobos
  Клиент: $CLIENT_ID
  Дата: $(date)
====================================================

ЦЕЛЕВЫЕ ПЛАТФОРМЫ:
  - Роутер Keenetic с установленным Entware
  - Роутер OpenWRT (любая версия)
  - Linux клиенты (Ubuntu/Debian)

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

  Скрипт автоматически определит платформу и:

  ДЛЯ KEENETIC:
  ✓ Установит wg-obfuscator (WireGuard встроен в прошивку!)
  ✓ Настроит WireGuard через RCI API (автоматически!)
  ✓ Создаст интерфейс с именем "Phobos-$CLIENT_ID"
  ✓ Активирует подключение

  ДЛЯ OPENWRT:
  ✓ Установит пакеты WireGuard (kmod-wireguard, wireguard-tools, luci-app-wireguard)
  ✓ Установит wg-obfuscator
  ✓ Настроит WireGuard через UCI (автоматически!)
  ✓ Создаст интерфейс "phobos_wg" и файрволл зону "phobos"
  ✓ Активирует подключение

  ДЛЯ LINUX (Ubuntu/Debian):
  ✓ Установит зависимости (jq, curl, tar) через apt-get
  ✓ Установит WireGuard через apt-get
  ✓ Установит wg-obfuscator
  ✓ Настроит WireGuard через systemd (wg-quick@$CLIENT_ID)
  ✓ Настроит obfuscator через systemd (phobos-obfuscator.service)
  ✓ Добавит порты в UFW (если установлен)
  ✓ Активирует оба сервиса

Шаг 4. Проверка результата
---------------------------------------
  Если автоматическая настройка прошла успешно:
    ✓ WireGuard интерфейс создан и активен
    ✓ Handshake установлен
    ✓ Готово к использованию!

  KEENETIC - Если RCI API недоступен (старая версия):
    ⚠ Требуется ручной импорт WireGuard конфигурации:

    1. Откройте веб-панель Keenetic (http://192.168.1.1 или http://my.keenetic.net)
    2. Перейдите: Интернет → WireGuard
    3. Нажмите "Добавить подключение"
    4. Выберите "Импортировать из файла"
    5. Укажите файл: /opt/etc/Phobos/$CLIENT_ID.conf
    6. Активируйте подключение

  OPENWRT - Если UCI недоступен:
    ⚠ Требуется ручная настройка через LuCI:

    1. Откройте веб-интерфейс LuCI (http://192.168.1.1)
    2. Перейдите: Network → Interfaces
    3. Создайте новый интерфейс с протоколом WireGuard
    4. Используйте параметры из файла: /etc/Phobos/$CLIENT_ID.conf
    5. Настройте файрволл зону для интерфейса

    Просмотр содержимого конфига:
      cat /etc/Phobos/$CLIENT_ID.conf

Шаг 5. Проверка соединения
---------------------------------------
  ./health-check.sh
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

  - $CLIENT_ID.conf                      - Конфиг WireGuard (dual-stack если IPv6 доступен)
  - wg-obfuscator.conf                   - Конфиг obfuscator (только IPv4)
  - install-router.sh                    - Скрипт установки (универсальный, определяет платформу)
  - router-configure-wireguard.sh        - Скрипт автоматической настройки WireGuard через RCI API (Keenetic)
  - router-configure-wireguard-openwrt.sh - Скрипт автоматической настройки WireGuard через UCI (OpenWRT)
  - health-check.sh                      - Скрипт проверки состояния (универсальный)
  - phobos-uninstall.sh                  - Скрипт удаления Phobos (универсальный)
  - detect-router-arch.sh                - Скрипт определения архитектуры роутера
  - bin/wg-obfuscator-*                  - Бинарники для разных архитектур
    - wg-obfuscator-mipsel                 (MIPS Little Endian)
    - wg-obfuscator-mips                   (MIPS Big Endian)
    - wg-obfuscator-aarch64                (ARM64)
    - wg-obfuscator-armv7                  (ARMv7)
    - wg-obfuscator-x86_64                 (x86_64 / AMD64)
  - README.txt                           - Этот файл

УСТАНОВЛЕННЫЕ ФАЙЛЫ НА УСТРОЙСТВЕ:

  KEENETIC:
  /opt/bin/wg-obfuscator                      - Бинарник obfuscator
  /opt/etc/Phobos/wg-obfuscator.conf          - Конфиг obfuscator
  /opt/etc/Phobos/$CLIENT_ID.conf             - Конфиг WireGuard
  /opt/etc/init.d/S49wg-obfuscator            - Init-скрипт obfuscator (Entware)

  OPENWRT:
  /usr/bin/wg-obfuscator                      - Бинарник obfuscator
  /etc/Phobos/wg-obfuscator.conf              - Конфиг obfuscator
  /etc/Phobos/$CLIENT_ID.conf                 - Конфиг WireGuard
  /etc/init.d/phobos-obfuscator               - Procd init-скрипт

  LINUX (Ubuntu/Debian):
  /usr/local/bin/wg-obfuscator                - Бинарник obfuscator
  /opt/Phobos/wg-obfuscator.conf              - Конфиг obfuscator
  /opt/Phobos/$CLIENT_ID.conf                 - Конфиг WireGuard (fallback)
  /etc/wireguard/$CLIENT_ID.conf              - Конфиг WireGuard (основной)
  /etc/systemd/system/phobos-obfuscator.service - Systemd service

ВАЖНЫЕ ЗАМЕЧАНИЯ:

  KEENETIC:
  - WireGuard встроен в прошивку Keenetic - установка не требуется
  - WireGuard настраивается АВТОМАТИЧЕСКИ через RCI API (Keenetic OS 4.0+)
  - Создаётся интерфейс с description="Phobos-$CLIENT_ID" для идентификации
  - Fallback конфиг сохраняется для ручного импорта при необходимости
  - При обновлении конфигурации существующий интерфейс обновится автоматически

  OPENWRT:
  - Устанавливаются пакеты: kmod-wireguard, wireguard-tools, luci-app-wireguard
  - WireGuard настраивается АВТОМАТИЧЕСКИ через UCI
  - Создаётся интерфейс "phobos_wg" и файрволл зона "phobos"
  - Зона "phobos" НЕ форвардит трафик автоматически - настройте маршрутизацию вручную
  - Файлы размещаются в корневой ФС: /usr/bin/, /etc/Phobos/
  - Init-скрипт: procd (/etc/init.d/phobos-obfuscator)

  LINUX:
  - Автоматическая установка WireGuard через apt-get
  - WireGuard настраивается через systemd (wg-quick@$CLIENT_ID)
  - Obfuscator управляется через systemd (phobos-obfuscator.service)
  - Автоматическая настройка UFW файрволла (если установлен)
  - Файлы размещаются в /opt/Phobos/ и /etc/wireguard/
  - Поддержка x86_64 и ARM64 архитектур

  ОБЩЕЕ:
  - Obfuscator управляется через init-скрипт (Entware/procd) или systemd (Linux)
  - Endpoint в конфиге указывает на локальный obfuscator (127.0.0.1:13255)
  - Поддержка dual-stack IPv4/IPv6 на всех платформах

УДАЛЕНИЕ PHOBOS:

  Для удаления Phobos выполните:
  1. cd /tmp/phobos-$CLIENT_ID
  2. chmod +x phobos-uninstall.sh
  3. ./phobos-uninstall.sh

  Скрипт автоматически:
  ✓ Остановит wg-obfuscator
  ✓ Удалит все WireGuard интерфейсы Phobos
  ✓ Удалит бинарник и конфигурационные файлы
  ✓ Удалит init-скрипт

ОТЛАДКА:

  KEENETIC/OPENWRT - Если возникли проблемы, проверьте:
  1. ps | grep wg-obfuscator
  2. /opt/etc/init.d/S49wg-obfuscator start     (Keenetic)
  3. /etc/init.d/phobos-obfuscator status       (OpenWRT)
  4. В веб-панели проверьте статус WireGuard

  LINUX - Если возникли проблемы, проверьте:
  1. systemctl status phobos-obfuscator
  2. systemctl status wg-quick@$CLIENT_ID
  3. journalctl -u phobos-obfuscator -n 50
  4. journalctl -u wg-quick@$CLIENT_ID -n 50
  5. wg show

ПОДДЕРЖКА:

  GitHub: https://github.com/Ground-Zerro/Phobos

====================================================
EOF

echo "==> Конвертация окончаний строк (CRLF -> LF)..."

find "$PACKAGE_DIR" -type f \( -name "*.sh" -o -name "*.conf" -o -name "*.template" \) -exec sed -i 's/\r$//' {} \;

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
