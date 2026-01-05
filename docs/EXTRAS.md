# EXTRAS

## Архитектура

```
Клиент → Роутер/Linux (WireGuard) → Obfuscator (127.0.0.1:13255) →
Internet → VPS Obfuscator (public_ip:random_port) → VPS WireGuard (127.0.0.1:51820) → Internet
```

### Поддерживаемые платформы

**Сервер:**
- **VPS**: Ubuntu Server 20.04/22.04

**Клиенты:**
- **Роутеры**: Keenetic/Netcraze (Entware), OpenWrt/LEDE, ImmortalWrt
- **Linux**: Ubuntu/Debian (стандартный режим и режим 3x-ui)

**Управление:**
- **Интерактивное меню** на VPS (команда `phobos`)
- **Telegram-бот** для управления клиентами

## Структура проекта

```
Phobos/
├── server/                                  # Серверные скрипты
│   ├── scripts/
│   │   ├── vps-install-dependencies.sh      # Установка зависимостей
│   │   ├── vps-build-obfuscator.sh          # Копирование готовых бинарников
│   │   ├── vps-wg-setup.sh                  # Установка WireGuard
│   │   ├── vps-obfuscator-setup.sh          # Установка obfuscator
│   │   ├── vps-client-add.sh                # Добавление клиента
│   │   ├── vps-client-remove.sh             # Удаление клиента
│   │   ├── vps-generate-package.sh          # Генерация пакета
│   │   ├── vps-init-all.sh                  # Полная установка
│   │   ├── vps-start-http-server.sh         # HTTP сервер
│   │   ├── vps-generate-install-command.sh  # Генератор токенов
│   │   ├── vps-cleanup-tokens.sh            # Очистка токенов
│   │   ├── vps-cleanup-orphaned-symlinks.sh # Очистка осиротевших симлинков
│   │   ├── vps-setup-token-cleanup.sh       # Настройка cron
│   │   ├── vps-health-check.sh              # Health check VPS
│   │   ├── vps-monitor-clients.sh           # Мониторинг клиентов
│   │   ├── vps-obfuscator-config.sh         # Настройка obfuscator
│   │   ├── vps-uninstall.sh                 # Удаление Phobos с VPS
│   │   ├── phobos-menu.sh                   # Интерактивное меню управления
│   │   ├── vps-install-menu.sh              # Установка меню phobos
│   │   ├── phobos-http-server.py            # Безопасный HTTP сервер
│   │   └── common-functions.sh              # Библиотека функций
│   └── templates/
├── client/                                  # Клиентские шаблоны
│   └── templates/
│       ├── install-router.sh.template                        # Установка на роутер
│       ├── router-configure-wireguard.sh.template            # Автонастройка WireGuard через RCI (Keenetic)
│       ├── router-configure-wireguard-openwrt.sh.template    # Автонастройка WireGuard через UCI (OpenWrt)
│       ├── health-check.sh.template                          # Health check
│       ├── phobos-uninstall.sh.template                      # Удаление Phobos
│       ├── detect-router-arch.sh.template                    # Определение архитектуры
│       ├── router-health-check.sh.template                   # Health check для роутеров
│       ├── router-uninstall.sh.template                      # Удаление с роутеров
│       └── 3xui.py.template                                  # Интеграция с 3x-ui
├── bot/                                     # Telegram-бот
│   └── phobos-bot/
│       ├── cmd/bot/main.go                  # Точка входа бота
│       ├── internal/                        # Логика бота
│       │   ├── bot.go                       # Основная логика
│       │   ├── handler.go                   # Обработчики команд
│       │   ├── config.go                    # Конфигурация
│       │   ├── backup_service.go            # Сервис бэкапов
│       │   ├── config_reloader.go           # Перезагрузка конфигурации
│       │   ├── health_server.go             # Health check сервер
│       │   └── database/                    # Работа с БД
│       ├── docs/                            # Документация бота
│       ├── bash/                            # Управляющие скрипты
│       │   ├── bot_deploy.sh                # Развертывание бота
│       │   ├── bot_toggle.sh                # Старт/стоп бота
│       │   └── run_sqlite_web.sh            # Веб-интерфейс БД
│       └── migrations/                      # Миграции БД
├── wg-obfuscator/                           # Бинарники obfuscator
│   └── bin/
│       ├── wg-obfuscator-x86_64             # VPS (x86_64)
│       ├── wg-obfuscator-mipsel             # MIPS Little Endian
│       ├── wg-obfuscator-mips               # MIPS Big Endian
│       ├── wg-obfuscator-aarch64            # ARM64
│       └── wg-obfuscator-armv7              # ARMv7
├── docs/                                    # Документация
│   ├── README.md                            # Оглавление документации
│   ├── README-server.md                     # Руководство администратора
│   ├── README-client.md                     # Руководство пользователя
│   ├── FAQ.md                               # Часто задаваемые вопросы
│   ├── TROUBLESHOOTING.md                   # Решение проблем
│   └── EXTRAS.md                            # Этот файл
├── README.md                                # Краткие сведения о проекте
└── NEWS.md                                  # История изменений

```

## Данные на VPS

```
/opt/Phobos/
├── server/
│   ├── server.env                       # OBFUSCATOR_PORT, KEY, IP, HTTP_PORT
│   ├── wg-obfuscator.conf
│   ├── server_private.key
│   └── server_public.key
├── clients/
│   └── <client_id>/
│       ├── client_private.key
│       ├── client_public.key
│       ├── wg-client.conf
│       ├── wg-obfuscator.conf
│       └── metadata.json
├── packages/
│   └── phobos-<client_id>.tar.gz        # Содержит 3 бинарника + скрипты
├── www/                                 # HTTP сервер
│   ├── index.html
│   ├── init/
│   │   └── <token>.sh                   # One-liner скрипты с TTL
│   └── packages/
│       └── <token>/                     # Симлинки на пакеты
├── tokens/
│   └── tokens.json                      # Метаданные токенов с TTL
├── bin/
│   ├── wg-obfuscator                    # Нативный для VPS (x86_64)
│   ├── wg-obfuscator-mipsel             # MIPS Little Endian
│   ├── wg-obfuscator-mips               # MIPS Big Endian
│   ├── wg-obfuscator-aarch64            # ARM64
│   └── wg-obfuscator-armv7              # ARMv7
└── logs/
    ├── phobos.log
    ├── cleanup.log                      # Логи очистки токенов
    ├── health-check.log                 # Логи health check
    └── phobos-menu.log                  # Логи интерактивного меню
```

## Данные на клиентах

### Роутер Keenetic/Netcraze/ImmortalWrt

```
/opt/bin/wg-obfuscator                     # Бинарник obfuscator
/opt/etc/init.d/S49wg-obfuscator           # Init-скрипт
/opt/etc/Phobos/
├── health-check.sh                        # Диагностика
├── phobos-uninstall.sh                    # Удаление Phobos
├── wg-obfuscator.conf                     # Конфиг obfuscator
└── <client_name>.conf                     # Конфиг WireGuard (fallback для ручного импорта)
```

**Примечание:** WireGuard настраивается автоматически через RCI API. Также доступен ручной импорт через веб-панель.

### Роутер OpenWrt

```
/usr/bin/wg-obfuscator                     # Бинарник obfuscator
/etc/init.d/wg-obfuscator                  # Init-скрипт
/etc/Phobos/
├── health-check.sh                        # Диагностика
├── phobos-uninstall.sh                    # Удаление Phobos
├── wg-obfuscator.conf                     # Конфиг obfuscator
└── <client_name>.conf                     # Конфиг WireGuard (fallback)
```

**Примечание:** WireGuard настраивается автоматически через UCI.

### Linux клиент

```
/usr/local/bin/wg-obfuscator               # Бинарник obfuscator
/opt/Phobos/
├── health-check.sh                        # Диагностика
├── phobos-uninstall.sh                    # Удаление Phobos
├── wg-obfuscator.conf                     # Конфиг obfuscator
└── <client_name>.conf                     # Исходный конфиг WireGuard
/etc/wireguard/phobos.conf                 # Конфиг WireGuard для systemd
/etc/systemd/system/
├── phobos-obfuscator.service              # Systemd service obfuscator
└── wg-quick@phobos.service.d/             # Override конфигурация WireGuard
```

**Режим 3x-ui:** При обнаружении 3x-ui устанавливается только obfuscator, WireGuard управляется через панель.

### Telegram-бот

```
/root/bot/phobos-bot/
├── bot                                    # Бинарный файл бота
├── config.yaml                            # Конфигурация
├── phobos-bot.db                          # База данных SQLite
├── backups/                               # Бэкапы БД
├── migrations/                            # Миграции БД
└── bash/                                  # Управляющие скрипты
/etc/systemd/system/phobos-bot.service     # Systemd service бота
```

## Настройка WireGuard

При установке через скрипт **WireGuard настраивается автоматически**. Не требуется ручной импорт!

Скрипт создаёт WireGuard интерфейс с именем "Phobos-{client_name}", настраивает все параметры и проверяет подключение.

**Ручная настройка:**

Если требуется ручной импорт через веб-панель:

1. Откройте админ-панель Keenetic (обычно http://192.168.1.1)
2. Перейдите: "Интернет" → "Другие подключения" → "WireGuard"
3. Выберите "Импортировать из файла"
4. Укажите путь к `{client_name}.conf` файлу (заберите с роутера: `/opt/etc/Phobos/{client_name}.conf`)
5. Активируйте подключение

## Мониторинг и отладка

### Автоматическая диагностика

**На VPS:**
```bash
sudo /opt/Phobos/repo/server/scripts/vps-health-check.sh      # Полная проверка системы
sudo /opt/Phobos/repo/server/scripts/vps-monitor-clients.sh   # Мониторинг клиентов
```

**На клиенте:**
```bash
/opt/etc/Phobos/health-check.sh         # Диагностика (Keenetic)
/opt/Phobos/health-check.sh             # Диагностика (Linux)
```

### Ручная диагностика

**На VPS:**
```bash
sudo wg show
sudo systemctl status wg-obfuscator
sudo journalctl -u wg-obfuscator -f
cat /opt/Phobos/server/server.env
sudo ss -ulpn | grep <OBFUSCATOR_PORT>
sudo tcpdump -i any udp and port <OBFUSCATOR_PORT>
```

**На роутере Keenetic:**
```bash
ps | grep wg-obfuscator
netstat -ulnp | grep 13255
ping 10.25.0.1
/opt/etc/init.d/S49wg-obfuscator restart
```

Проверьте статус WireGuard через веб-панель Keenetic.

## Поддерживаемые платформы

### VPS

- Ubuntu Server (рекомендуется Ubuntu 20.04/22.04)

### Роутеры

- Keenetic с установленным Entware
  - WireGuard встроен в прошивку
  - Управление через веб-панель

### Архитектуры роутеров

- **mipsel** (MIPS Little Endian) - наиболее распространенные модели:
  - Giga (KN-1010/1011), Ultra (KN-1810), Viva (KN-1910/1912), Extra (KN-1710/1711/1712), City (KN-1510/1511), Start (KN-1110), Lite (KN-1310/1311), 4G (KN-1210/1211), Omni (KN-1410), Air (KN-1610), Air Primo (KN-1611), Mirand (KN-2010), Zyx (KN-2110), Musubi (KN-2210), Grid (KN-2410), Wave (KN-2510), Sky (KN-2610), Pro (KN-2810), Combo (KN-2910), Spiner (KN-3010), Doble (KN-3111), Doble Plus (KN-3112), Station (KN-3210) - первые версии, Cloud (KN-3510) - первые версии, Hurricane (KN-4010) - первые версии, Tornado (KN-4110) - первые версии и др.

- **aarch64** (ARM64) - современные мощные модели:
  - Peak (KN-2710), Titan (KN-1920/1921), Hero 4G (KN-2310), Hopper (KN-3810), Play (KN-3110), Station (KN-3210) - более поздние версии, Omnia (KN-3310), Giant (KN-3410), Cloud (KN-3510) - более поздние версии, Link (KN-3610), Anchor (KN-3710), Arrow (KN-3910), Hurricane (KN-4010) - более поздние версии, Tornado (KN-4110) - более поздние версии, Hurricane II (KN-4210), Tornado II (KN-4310), Hurricane III (KN-4410), Tornado III (KN-4510), Magic (KN-4610), Switch (KN-1420), Switch 16 (KN-1421), XXL (KN-4710), Grand (KN-4810), Zyxel (KN-4910), Park (KN-5010), Lette (KN-5110)

- **mips** (MIPS Big Endian) - редкие старые модели:
  - Некоторые ранние версии моделей (до 2015 года), отдельные экземпляры старых моделей

## Управление системой

### Интерактивное меню на VPS

После установки доступна команда `phobos` для интерактивного управления:

- Управление сервисами (WireGuard, obfuscator, HTTP сервер)
- Управление клиентами (создание, удаление, пересоздание)
- Системные функции (бэкапы, очистка, мониторинг)
- Настройка параметров obfuscator

### Telegram-бот

Бот предоставляет следующие возможности:

**Управление клиентами:**
- Создание/удаление клиентов
- Просмотр статистики подключений
- Мониторинг активности

**Система уровней:**
- **Basic** - обычные пользователи
- **Premium** - премиум пользователи (защита от автоудаления)
- **Moderator** - модераторы (управление пользователями)
- **Admin** - администраторы (полный доступ)

**Автоматизация:**
- **Watchdog** - автоматическое удаление неактивных клиентов
- **Config Reloader** - горячая перезагрузка конфигурации
- **Backup Service** - автоматические бэкапы БД
- **Health Server** - HTTP endpoint для мониторинга

**Управление ботом:**
```bash
sudo /root/bot/phobos-bot/bash/bot_toggle.sh  # Старт/стоп бота
sudo systemctl status phobos-bot               # Статус
sudo journalctl -u phobos-bot -f               # Логи
```

## Безопасность

- Приватные ключи хранятся с правами 600
- Случайный порт obfuscator затрудняет его обнаружение
- Симметричный ключ обфускации генерируется криптографически безопасно