# Phobos

Автоматизация развертывания защищенного WireGuard с обфускацией трафика через `wg-obfuscator`.

## Описание

**Phobos** — комплексное решение для автоматизации настройки обфусцированного WireGuard соединения между VPS сервером и клиентами. Включает серверные скрипты, клиентские установщики для роутеров (Keenetic, OpenWrt, ImmortalWrt) и Linux систем (Ubuntu/Debian), а также Telegram-бот для управления клиентами.

### Основные компоненты

- **Серверная часть** - автоматизация развертывания WireGuard с обфускацией на VPS
- **Клиентская часть** - установщики для роутеров (Keenetic/OpenWrt/ImmortalWrt) и Linux систем
- **Telegram-бот** - управление клиентами, мониторинг, автоматическая очистка неактивных
- **Интеграция с 3x-ui** - поддержка установки только obfuscator для работы с панелью 3x-ui

## Быстрый старт

### 1. Установка на VPS

Запустите установку:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/main/phobos-deploy.sh)" </dev/tty
```

<details>
  <summary>Подробней</summary>

  Система выполнит:
  - Проверку и установку необходимых системных зависимостей
  - Копирование готовых бинарников wg-obfuscator для VPS сервера и всех поддерживаемых архитектур роутеров (mipsel, mips, aarch64, armv7, x86)
  - Создание и настройку конфигурационных файлов для WireGuard и obfuscator с безопасными портами
  - Автоматическое определение IPv6 адреса (если доступен)
  - Создание первого клиента
  - Генерацию установочного пакета с бинарниками и конфигурациями для Keenetic и OpenWrt
  - Запуск HTTP-сервера для раздачи установочных пакетов
  - Генерацию одноразовой команды установки с уникальным токеном
  - Вывод готовой HTTP-ссылки для установки на роутере
</details>

### 2. Установка на клиенте

#### Keenetic/Netcraze/ImmortalWrt (Entware)

Отправьте ссылку клиенту, он выполняет ее на роутере в терминале Entware, пример:

```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Установит jq для корректного парсинга JSON
  - Скачает установочный пакет
  - Определит архитектуру роутера
  - Установит правильный бинарник wg-obfuscator
  - Настроит автозапуск obfuscator
  - Настроит WireGuard через RCI API
  - Создаст интерфейс "Phobos-{client_name}"
  - Активирует подключение
  - Проверит создание интерфейса
  - Развернет скрипты health-check и uninstall
</details>

#### OpenWrt

Отправьте ссылку клиенту, он выполняет ее на роутере через SSH, пример:

```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sh
```
<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Установит пакеты WireGuard (kmod-wireguard, wireguard-tools, luci-app-wireguard)
  - Скачает установочный пакет
  - Определит архитектуру роутера
  - Установит правильный бинарник wg-obfuscator
  - Настроит автозапуск obfuscator
  - Настроит WireGuard через UCI
  - Создаст интерфейс "phobos_wg" и firewall зону "phobos"
  - Активирует подключение
  - Проверит создание интерфейса
  - Развернет скрипты health-check и uninstall
</details>

#### Linux (Ubuntu/Debian)

Отправьте ссылку клиенту, он выполняет ее на Linux компьютере через SSH или терминал, пример:

```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sudo sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Определит режим установки (автоматическое определение 3x-ui панели)
  - Установит WireGuard, resolvconf и net-tools через apt-get (стандартный режим)
  - Скачает установочный пакет
  - Определит архитектуру системы
  - Установит правильный бинарник wg-obfuscator
  - Настроит автозапуск obfuscator через systemd
  - Настроит WireGuard через systemd с фиксированным интерфейсом "phobos" (стандартный режим)
  - Настроит VPN как запасной интерфейс (не перехватывает системный трафик)
  - Создаст зависимость WireGuard от obfuscator (стандартный режим)
  - Активирует подключение
  - Проверит создание интерфейса и туннеля
  - Развернет скрипты health-check и uninstall

  **Особенности Linux клиента:**
  - VPN настроен как запасной интерфейс (`Table = off`)
  - Системный трафик не перехватывается автоматически
  - Для направления трафика через VPN используйте команды из документации
  - Интерфейс называется "phobos" (аналогично OpenWrt "phobos_wg")

  **Режим 3x-ui:**
  - При обнаружении панели 3x-ui устанавливается только obfuscator
  - WireGuard управляется через панель 3x-ui
  - Автоматическая интеграция конфигурации через скрипт 3xui.py
</details>

## Управление системой

### Интерактивное меню на VPS

Меню на VPS вызывается командой:
```
phobos
```

**Основные возможности меню:**
- Управление сервисами (start/stop/status/logs для WireGuard, obfuscator, HTTP сервера)
- Управление клиентами (создание, удаление, пересоздание конфигураций)
- Системные функции (health checks, мониторинг клиентов, очистка токенов)
- Резервное копирование конфигураций
- Настройка параметров obfuscator

### Telegram-бот для управления клиентами

Phobos включает Telegram-бот для удобного управления:

**Основные возможности:**
- Создание и удаление клиентов через Telegram
- Просмотр статистики и мониторинг подключений
- Система уровней пользователей (basic, premium, moderator, admin)
- Автоматический watchdog для удаления неактивных клиентов
- Обратная связь и поддержка
- Health check endpoint
- Автоматические бэкапы базы данных

**Команды бота:**
- `/start` - Начало работы с ботом
- `/create` - Создать нового клиента
- `/stat` - Просмотр статистики
- `/delete` - Удалить клиента
- `/info` - Информация о боте
- `/help` - Справка по командам
- `/feedback` - Отправить обратную связь
- `/admin` - Панель администратора (для администраторов)

> **Примечание:** Бот имеет работающий функционал, но не является законченным продуктом. Он разработан как гибкая основа, которую легко можно доработать под свои нужды. См. документацию бота в `bot/phobos-bot/docs/`

## Удаление

### Удаление с VPS сервера

Для полного удаления Phobos с VPS сервера:

```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh
```

Для сохранения резервной копии данных клиентов:

```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh --keep-data
```

### Удаление с клиента

#### Keenetic/Netcraze

Для полного удаления Phobos с роутера Keenetic/Netcraze:

```bash
/opt/etc/Phobos/phobos-uninstall.sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Остановит wg-obfuscator
  - Удалит все WireGuard интерфейсы Phobos через RCI API
  - Удалит бинарники и конфигурационные файлы
  - Удалит init-скрипт
  - Сохранит конфигурацию роутера
</details>

#### OpenWrt

Для полного удаления Phobos с роутера OpenWrt:

```bash
/etc/Phobos/phobos-uninstall.sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Остановит wg-obfuscator
  - Удалит WireGuard интерфейс и firewall зону через UCI
  - Удалит бинарники и конфигурационные файлы
  - Удалит init-скрипт
  - Сохранит конфигурацию роутера
</details>

#### Linux (Ubuntu/Debian)

Для полного удаления Phobos с Linux компьютера:

```bash
sudo /opt/Phobos/phobos-uninstall.sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически:
  - Остановит phobos-obfuscator и wg-quick@phobos
  - Удалит WireGuard интерфейс "phobos" и systemd override конфигурацию
  - Удалит systemd сервисы (phobos-obfuscator.service)
  - Удалит бинарники (/usr/local/bin/wg-obfuscator)
  - Удалит конфигурационные файлы (/opt/Phobos, /etc/wireguard/phobos.conf)
</details>

## Совместимость и поддерживаемые платформы

### Сервер (VPS)
Протестированно и рекомендуется к использованию на **Ubuntu 20.04** и **Ubuntu 22.04**.
Желательна установка на **чистый VPS** без предварительно установленных сервисов или конфигураций.
> Совместимость с другими дистрибутивами Linux и сторонними сервисами **не проверялась**.

### Клиенты

**Роутеры:**
- **Keenetic** (все модели с Entware) - mipsel, aarch64, mips
- **Netcraze** (устройства Keenetic под другой маркой)
- **OpenWrt/LEDE** (все архитектуры) - mipsel, mips, aarch64, armv7, x86_64
- **ImmortalWrt** - форк OpenWrt с дополнительными возможностями

**Linux системы:**
- **Ubuntu/Debian** - стандартная установка WireGuard + obfuscator
- **Системы с 3x-ui панелью** - автоматическое определение и установка только obfuscator

**Поддерживаемые архитектуры:**
- x86_64 (VPS, PC-роутеры)
- mipsel (большинство Keenetic, бюджетные TP-Link)
- mips (старые модели TP-Link, D-Link)
- aarch64 (современные Keenetic, Linksys, Netgear)
- armv7 (GL.iNet, Raspberry Pi 2/3)

## License

This project is licensed under GPL-3.0.
See the [LICENSE](./LICENSE) file for full terms.

## Благодарности

- [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) — инструмент обфускации WireGuard трафика /[Поблагадарить Алексея и поддержать его разработку](https://boosty.to/cluster)/
- [WireGuard](https://www.wireguard.com/) — современный VPN протокол

## Поддержка

**Угостить автора чашечкой какао можно на** [Boosty](https://boosty.to/ground_zerro) ❤️
