# Phobos Server - Руководство администратора

## Содержание

- [Введение](#введение)
- [Системные требования](#системные-требования)
- [Установка](#установка)
- [Управление клиентами](#управление-клиентами)
- [Интерактивное меню управления](#интерактивное-меню-управления)
- [Мониторинг](#мониторинг)
- [Обслуживание](#обслуживание)
- [Удаление](#удаление)
- [Решение проблем](#решение-проблем)

## Введение

Phobos - это система автоматизации развертывания WireGuard с обфускацией трафика через wg-obfuscator. Этот документ описывает установку и управление серверной частью.

### Архитектура системы

```
Клиент → WireGuard → Локальный obfuscator → Интернет →
→ Серверный obfuscator → Серверный WireGuard → Интернет
```

## Системные требования

### Минимальные требования

- ОС: Ubuntu Server 20.04+ (рекомендуется 22.04 LTS)
- CPU: 1 ядро
- RAM: 512 MB
- Диск: 2 GB свободного места
- Сеть: Публичный IP адрес, UDP порт для obfuscator

### Рекомендуемые требования

- CPU: 2+ ядра
- RAM: 1 GB+
- Диск: 5 GB+ SSD
- Сеть: 100+ Mbit/s

## Установка

### Быстрая установка (рекомендуется)

Запустите автоматическую установку:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/main/phobos-deploy.sh)" </dev/tty
```

Скрипт автоматически:
- Установит необходимые зависимости (wget, curl, jq, python3, openssl, wireguard)
- Клонирует репозиторий в /opt/Phobos/repo
- Скопирует готовые бинарники wg-obfuscator
- Определит IPv6 адрес (если доступен) с двойной проверкой
- Сгенерирует безопасные порты (100-700) для obfuscator и HTTP сервера
- Настроит WireGuard и obfuscator
- Создаст первого клиента
- Запустит HTTP сервер для раздачи пакетов

### Ручная установка

Клонируйте репозиторий на VPS:

```bash
git clone https://github.com/Ground-Zerro/Phobos.git /opt/Phobos/repo
cd /opt/Phobos/repo
```

Запустите полную установку:

```bash
sudo ./server/scripts/vps-init-all.sh
```

После установки будет создано интерактивное меню `phobos`. Запустите его командой:

```bash
sudo phobos
```

### Проверка установки

```bash
sudo systemctl status wg-quick@wg0
sudo systemctl status wg-obfuscator
sudo systemctl status phobos-http
sudo wg show
```

## Управление клиентами

### Интерактивное меню управления

После установки система включает интерактивное меню управления. Запустите команду `phobos` для доступа ко всем функциям системы:

```bash
phobos
```

**Основные возможности меню:**
- Управление сервисами (start/stop/status/logs для WireGuard, obfuscator, HTTP сервера)
- Управление клиентами (создание, удаление, пересоздание конфигураций)
- Системные функции (health checks, мониторинг клиентов, очистка токенов)
- Резервное копирование конфигураций
- Настройка параметров obfuscator

### Создание нового клиента вручную

```bash
sudo /opt/Phobos/repo/server/scripts/vps-client-add.sh <client_name>
```

### Удаление клиента вручную

```bash
sudo /opt/Phobos/repo/server/scripts/vps-client-remove.sh <client_name>
```

## Интерактивное меню управления

### Запуск меню

После установки Phobos доступна команда `phobos` для интерактивного управления системой:

```bash
phobos
```

### Управление сервисами

В меню можно управлять всеми сервисами системы:
- WireGuard - start/stop/status/logs
- Obfuscator - start/stop/status/logs
- HTTP сервер - start/stop/status/logs

### Управление клиентами

В меню можно:
- Просматривать список клиентов
- Создавать новых клиентов
- Удалять существующих клиентов
- Пересоздавать конфигурации клиентов
- Генерировать новые установочные пакеты
- Генерировать новые ссылки для установки

### Системные функции

В меню доступны:
- Проверка состояния системы
- Мониторинг клиентов
- Очистка просроченных токенов
- Очистка осиротевших симлинков
- Резервное копирование конфигураций
- Настройка параметров obfuscator

**Настройка параметров obfuscator:**
- Изменение порта прослушивания
- Изменение IP интерфейса
- Генерация нового ключа обфускации
- Изменение уровня логирования
- Изменение режима маскировки
- Изменение таймаута неактивности
- Изменение максимума dummy-пакетов
- Просмотр и применение изменений
- Массовое обновление клиентов при изменении критических параметров

**Особенности синхронизации параметров с клиентами:**
- При создании новых клиентов все параметры obfuscator (включая max-dummy) берутся из текущей серверной конфигурации
- При изменении параметров через интерактивное меню можно использовать "Массовое обновление клиентов" для синхронизации значений у всех клиентов
- Параметр max-dummy автоматически синхронизируется между сервером и клиентами

Скрипт автоматически выполняет ВСЕ необходимые действия:
- Генерирует ключевую пару WireGuard
- Создает конфигурации WireGuard и obfuscator
- Выделяет IP адрес из подсети туннеля
- Создает установочный пакет для роутера со всеми бинарниками
- Включает скрипт автоматической настройки WireGuard через RCI API
- Генерирует токен и HTTP ссылку для установки
- Выдает готовую команду для клиента

Установочный пакет включает скрипт автоматической настройки WireGuard через RCI API на роутерах Keenetic. Ручной импорт конфигурации не требуется!

**Пример вывода:**
```
==> Клиент myclient успешно создан!
...
Отправьте клиенту следующую команду для установки:

wget -O - http://100.100.100.101:8080/init/a1b2c3d4e5f6.sh | sh

ВАЖНО: Токен действителен до 2025-11-03 12:00:00
```

## Удаление

### Полное удаление Phobos

```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh
```

Скрипт удалит:
- Все systemd сервисы (wg-quick@wg0, wg-obfuscator, phobos-http)
- Конфигурации WireGuard (/etc/wireguard/wg0.conf)
- Cron задачи
- Бинарные файлы (/usr/local/bin/wg-obfuscator, /usr/local/bin/phobos)
- Все данные в /opt/Phobos/

### Удаление с сохранением данных

Для сохранения резервной копии клиентских данных:

```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh --keep-data
```

Резервная копия будет создана в `/root/phobos-backup-<timestamp>/` и включает:
- Конфигурации всех клиентов
- Установочные пакеты
- Ключи сервера
- Параметры сервера (server.env)

## Решение проблем

### WireGuard не запускается

```bash
sudo wg-quick down wg0
sudo wg-quick up wg0
sudo journalctl -u wg-quick@wg0 -n 50
```

### Obfuscator не слушает порт

```bash
sudo systemctl restart wg-obfuscator
sudo ss -ulnp | grep <OBFUSCATOR_PORT>
sudo journalctl -u wg-obfuscator -n 50
```

### Клиенты не могут подключиться

Проверьте:
1. Obfuscator запущен и слушает правильный порт
2. WireGuard запущен
3. Ключи клиента добавлены на сервер
4. Порт obfuscator доступен извне

```bash
sudo wg show
sudo systemctl status wg-obfuscator
sudo ss -ulnp | grep <OBFUSCATOR_PORT>
```

### HTTP сервер недоступен

```bash
sudo systemctl status phobos-http
sudo ss -tlnp | grep :8080
sudo systemctl restart phobos-http
```

### Проверка сетевого стека

```bash
sudo tcpdump -i any -n udp and port <OBFUSCATOR_PORT>
ping 10.8.0.2
```

## Параметры конфигурации

### /opt/Phobos/server/server.env

```bash
OBFUSCATOR_PORT=<random 100-700, исключая зарезервированные>
OBFUSCATOR_KEY=<random 3 char>
SERVER_PUBLIC_IP=<auto-detected IPv4>
SERVER_PUBLIC_IP_V6=<auto-detected IPv6 if available>
WG_LOCAL_ENDPOINT=127.0.0.1:51820
HTTP_PORT=<random 100-700, исключая OBFUSCATOR_PORT>
```

**Примечания:**
- Порты генерируются в диапазоне 100-700 с исключением IANA зарезервированных портов
- IPv6 определяется с двойной проверкой через несколько сервисов для надежности
- HTTP_PORT исключает конфликт с OBFUSCATOR_PORT

### /etc/wireguard/wg0.conf

- Address: 10.8.0.1/24
- ListenPort: 51820 (localhost only)
- PostUp/PostDown: iptables для NAT

### /opt/Phobos/server/wg-obfuscator.conf

- source-if: 0.0.0.0
- source-lport: <OBFUSCATOR_PORT>
- target: 127.0.0.1:51820
- key: <OBFUSCATOR_KEY>

## Контакты и поддержка

- GitHub: https://github.com/Ground-Zerro/Phobos
- Issues: https://github.com/Ground-Zerro/Phobos/issues
