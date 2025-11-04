# EXTRAS

## Архитектура

```
Клиент → Роутер Keenetic (WireGuard встроен) → Obfuscator (127.0.0.1:13255) →
Internet → VPS Obfuscator (public_ip:random_port) → VPS WireGuard (127.0.0.1:51820) → Internet
```

### Поддерживаемые платформы

- **VPS**: Ubuntu Server
- **Роутер**: Keenetic с установленным Entware

## Структура проекта

```
Phobos/
├── server/
│   ├── scripts/
│   │   ├── vps-install-dependencies.sh      # Установка зависимостей
│   │   ├── vps-build-obfuscator.sh          # Сборка wg-obfuscator
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
│   │   ├── phobos-menu.sh                   # Интерактивное меню управления
│   │   ├── vps-install-menu.sh              # Установка меню phobos
│   │   └── common-functions.sh              # Библиотека функций
│   └── templates/
├── client/
│   └── templates/
│       ├── install-router.sh.template                # Установка на роутер
│       ├── router-configure-wireguard.sh.template    # Автонастройка WireGuard через RCI
│       ├── router-health-check.sh.template           # Health check роутера
│       └── detect-router-arch.sh.template            # Определение архитектуры
├── docs/
│   ├── README-server.md                     # Руководство администратора
│   ├── README-client.md                     # Руководство пользователя
│   ├── FAQ.md                               # Часто задаваемые вопросы
│   ├── TROUBLESHOOTING.md                   # Решение проблем
│   └── EXTRAS.md                            # Этот файл
└── README.md                                # Кратккие седения о проекте

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
│   └── wg-obfuscator-aarch64            # ARM64
└── logs/
    ├── phobos.log
    ├── cleanup.log                      # Логи очистки токенов
    ├── health-check.log                 # Логи health check
    └── phobos-menu.log                  # Логи интерактивного меню
```

## Данные на роутере Keenetic

```
/opt/bin/wg-obfuscator                     # Бинарник obfuscator
/opt/etc/init.d/S49wg-obfuscator           # Init-скрипт
/opt/etc/Phobos/
├── router-health-check.sh                 # Диагностика роутера
├── wg-obfuscator.conf                     # Конфиг obfuscator
└── <client_name>.conf                     # Конфиг WireGuard (fallback для ручного импорта)
```

**Примечание:** WireGuard настраивается автоматически через RCI API. Также доступен ручной импорт через веб-панель.

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
sudo ./server/scripts/vps-health-check.sh      # Полная проверка системы
sudo ./server/scripts/vps-monitor-clients.sh   # Мониторинг клиентов
```

**На роутере Keenetic:**
```bash
/opt/etc/Phobos/router-health-check.sh         # Диагностика роутера
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
ping 10.8.0.1
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

## Безопасность

- Приватные ключи хранятся с правами 600
- Случайный порт obfuscator затрудняет его обнаружение
- Симметричный ключ обфускации генерируется криптографически безопасно