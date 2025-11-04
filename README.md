# Phobos

Автоматизация развертывания защищенного WireGuard VPN с обфускацией трафика через `wg-obfuscator`.

## Описание

**Phobos** автоматизирует настройку обфусцированного WireGuard соединения между VPS сервером и клиентскими роутерами (Entware). Обфускация трафика затрудняет обнаружение и блокировку VPN.

### Ключевые особенности

- Случайная генерация UDP порта для obfuscator (10000-60000)
- Сборка wg-obfuscator из исходников с кросс-компиляцией для роутеров (mipsel, mips, aarch64)
- Автоматическое определение архитектуры роутера и выбор правильного бинарника
- Управление через итерактивное меню (VPS)

## Архитектура

```
Клиент → Роутер Keenetic (WireGuard встроен) → Obfuscator (127.0.0.1:13255) →
Internet → VPS Obfuscator (public_ip:random_port) → VPS WireGuard (127.0.0.1:51820) → Internet
```

### Поддерживаемые платформы

- **VPS**: Ubuntu Server
- **Роутер**: Keenetic с установленным Entware

## Функции

### Интерактивное меню управления

Система включает интерактивное меню управления. Запустите команду `phobos` для доступа ко всем функциям системы.

**Основные возможности меню:**
- Управление сервисами (start/stop/status/logs для WireGuard, obfuscator, HTTP сервера)
- Управление клиентами (создание, удаление, пересоздание конфигураций)
- Системные функции (health checks, мониторинг клиентов, очистка токенов)
- Резервное копирование конфигураций
- Настройка параметров obfuscator

## Быстрый старт

### 1. Установка на VPS

Клонируйте репозиторий на VPS:

```bash
git clone https://github.com/yourusername/Phobos.git
cd Phobos
```

Запустите полную установку:

```bash
sudo ./server/scripts/vps-init-all.sh
```

После установки будет создано интерактивное меню `phobos`. Запустите его командой:

```bash
sudo phobos
```

### 2. Создание клиента

Добавьте нового клиента в меню `phobos`,  

или вручную:
```bash
sudo ./server/scripts/vps-client-add.sh home-router
```

Система автоматически:
- Создаст клиента с конфигурацией WireGuard
- Сгенерирует установочный пакет со всеми бинарниками
- Создаст одноразовую команду установки с токеном
- Выдаст готовую HTTP ссылку для роутера, например:

```bash
wget -O - http://100.100.100.101:8080/init/a1b2c3d4e5f6.sh | sh
```

### 3. Установка на роутер Keenetic (полностью автоматическая)

Отправьте команду клиенту. Клиент выполняет на роутере в терминале:

```bash
wget -O - http://100.100.100.101:8080/init/a1b2c3d4e5f6.sh | sh
```

Скрипт автоматически:
- Скачает установочный пакет
- Определит архитектуру роутера
- Установит правильный бинарник wg-obfuscator
- Настроит автозапуск obfuscator
- Настроит WireGuard через RCI API
- Создаст интерфейс "Phobos-{client_name}"
- Активирует подключение
- Проверит handshake

### 4. Настройка WireGuard

**Автоматическая настройка (Keenetic OS):**

При установке через скрипт WireGuard настраивается **автоматически** через RCI API. Не требуется ручной импорт!

Скрипт создаёт WireGuard интерфейс с именем "Phobos-{client_name}", настраивает все параметры и проверяет подключение.

**Ручная настройка (если автоматическая не сработала):**

Если RCI API, потребуется ручной импорт через веб-панель:

1. Откройте админ-панель Keenetic (обычно http://192.168.1.1)
2. Перейдите: "Интернет" → "Другие подключения" → "WireGuard"
3. Выберите "Импортировать из файла"
4. Укажите путь к `{client_name}.conf` файлу (заберите с роутера: `/opt/etc/Phobos/{client_name}.conf`)
5. Активируйте подключение

### 5. Проверка соединения

Через веб-панель Keenetic проверьте статус WireGuard подключения.

На VPS:

```bash
sudo wg show wg0
sudo systemctl status wg-obfuscator
```

## Тестирование

Проект протестирован на реальном оборудовании:

**VPS:**
- ОС: Ubuntu Server
- WireGuard: работает на 127.0.0.1:51820
- Obfuscator: работает на 0.0.0.0:18416 (случайный порт)

**Роутер:**
- Модель: Keenetic
- Архитектура: mipsel, aarch64
- Obfuscator: работает на 127.0.0.1:13255
- WireGuard: настраивается автоматически через RCI API

**Проверенный функционал:**
- ✅ Полный цикл установки VPS через vps-init-all.sh
- ✅ Создание клиента через vps-client-add.sh
- ✅ Автоматическая генерация HTTP ссылки для установки
- ✅ Установка на роутере через wget one-liner
- ✅ Автоопределение архитектуры роутера (mipsel)
- ✅ Запуск и автозагрузка wg-obfuscator на роутере
- ✅ Автоматическая настройка WireGuard через RCI API
- ✅ Проверка handshake после настройки
- ✅ Совместимость init-скрипта с BusyBox/ash
- ✅ Симметричная обфускация на обеих сторонах (одинаковый ключ)
- ✅ Peer-подключение между VPS и роутером

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
│   └── TROUBLESHOOTING.md                   # Решение проблем
└── README.md                                # Этот файл
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

## План развития

### Приоритет 1 (MVP) ✅ ЗАВЕРШЕНО

1. ✅ Сборка wg-obfuscator из исходников с кросс-компиляцией (mipsel, mips, aarch64)
2. ✅ Установка WireGuard и obfuscator на Ubuntu VPS
3. ✅ Создание клиентов через терминал + автоматическая генерация пакетов
4. ✅ Установка obfuscator на роутерах Keenetic
5. ✅ Автоматическая настройка WireGuard через RCI API
6. ✅ Генерация конфигов (fallback для ручного импорта при необходимости)
7. ✅ Полная автоматизация VPS-установки (vps-init-all.sh)
8. ✅ Протестировано на реальном оборудовании

### Приоритет 2 (Автоматизация) ✅ ЗАВЕРШЕНО

8. ✅ HTTP сервер для раздачи пакетов (phobos-http.service)
9. ✅ Генерация токенов и временных ссылок (TTL support)
10. ✅ One-liner команда установки для роутеров (`wget | sh`)
11. ✅ Автоматическая очистка просроченных токенов (cron)

### Приоритет 3 (Мониторинг и документация) ✅ ЗАВЕРШЕНО

12. ✅ Health checks для VPS и роутера (vps-health-check.sh, router-health-check.sh)
13. ✅ Мониторинг клиентов в реальном времени (vps-monitor-clients.sh)
14. ✅ Определение моделей Keenetic и архитектур (detect-router-arch.sh)
15. ✅ Полная документация (README-server.md, README-client.md, FAQ.md, TROUBLESHOOTING.md)
16. ⚠️ Unit тесты для скриптов — пропущено (низкий приоритор для MVP)

### Приоритет 4 (Дополнительные возможности) — ⚠️ ЗАВЕРШЕНО ЧАСТИЧНО

17. ✅ Интерактивное меню управления (`phobos`)
18. ❌ Статистика и аналитика использования
19. ❌ Ansible плейбуки для автоматического развертывания
20. ❌ Поддержка других платформ (Windows, macOS, Android)

## Документация

Доступна документация:
- **[README-server.md](.docs/README-server.md)** - руководство администратора
- **[README-client.md](.docs/README-client.md)** - руководство пользователя
- **[FAQ.md](.docs/FAQ.md)** - часто задаваемые вопросы (40+ ответов)
- **[TROUBLESHOOTING.md](.docs/TROUBLESHOOTING.md)** - решение проблем

## Безопасность

- Приватные ключи хранятся с правами 600
- Случайный порт obfuscator затрудняет его обнаружение
- Симметричный ключ обфускации генерируется криптографически безопасно

## License

This project is licensed under a **Proprietary License**.  
Viewing, cloning, and private non-commercial use are permitted.  
Redistribution, modification, or any commercial use are prohibited without the written consent of the maintainer.  
See the [LICENSE](./LICENSE) file for full terms.

## External dependency: wg-obfuscator (GPL-3.0)

This repository provides a wrapper that automates configuration or invocation of `wg-obfuscator`.  
This project does NOT include, distribute, or modify `wg-obfuscator` source or binaries.

/* RU — для внутренней справки */
Этот проект содержит только обвязку. Бинарники/исходники `wg-obfuscator` не включены и не распространяются здесь.

## Автор

[Ground-Zerro](https://github.com/Ground-Zerro)

**Угостить автора чашечкой какао можно на** [Boosty](https://boosty.to/ground_zerro) ❤️

## Благодарности

- [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) — инструмент обфускации WireGuard трафика /[Поблагадарить Алексея и поддержать его разработку](https://boosty.to/cluster)/
- [WireGuard](https://www.wireguard.com/) — современный VPN протокол
