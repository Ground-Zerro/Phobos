# Phobos

Автоматизация развертывания защищенного WireGuard с обфускацией трафика через `wg-obfuscator`.

## Описание

**Phobos** — комплексное решение для автоматизации настройки обфусцированного WireGuard соединения между VPS сервером и клиентами. Включает серверные скрипты и клиентские установщики для роутеров (Keenetic/Netcraze, OpenWrt, ImmortalWrt) и Linux систем (Ubuntu/Debian).

### Основные компоненты

- **Серверная часть** - автоматизация развертывания WireGuard с обфускацией на VPS
- **Клиентская часть** - установщики для роутеров (Keenetic/Netcraze, OpenWrt, ImmortalWrt) и Linux систем
- **Интеграция с 3x-ui** - поддержка установки только obfuscator для работы с панелью 3x-ui

## Быстрый старт

### 1. Установка на VPS

Запустите установку:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/main/phobos-deploy.sh)" </dev/tty
```

### 2. Установка на клиенте

**Keenetic/Netcraze/ImmortalWrt** (терминал Entware):
```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sh
```

**OpenWrt** (SSH):
```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sh
```

**Linux (Ubuntu/Debian)** (SSH или терминал):
```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sudo sh
```

<details>
  <summary>Подробней</summary>

  Скрипт автоматически определяет платформу и архитектуру, устанавливает wg-obfuscator, настраивает автозапуск, конфигурирует WireGuard, активирует подключение, развёртывает скрипты health-check и uninstall.

  **Keenetic/Netcraze:** настройка через RCI API, интерфейс `Phobos-{client_name}`
  **OpenWrt/ImmortalWrt:** установка kmod-wireguard, wireguard-tools, luci-app-wireguard; настройка через UCI, интерфейс `phobos_wg`, firewall зона `phobos`
  **Linux:** установка через apt-get и systemd, интерфейс `phobos`, VPN как запасной интерфейс (`Table = off`). При обнаружении 3x-ui — только obfuscator через 3xui.sh.
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
- Настройка параметров obfuscator (порты, ключи, уровни маскировки, пул адресов)

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

**Keenetic/Netcraze:**
```bash
/opt/etc/Phobos/phobos-uninstall.sh
```

**OpenWrt/ImmortalWrt:**
```bash
/etc/Phobos/phobos-uninstall.sh
```

**Linux (Ubuntu/Debian):**
```bash
sudo /opt/Phobos/phobos-uninstall.sh
```

<details>
  <summary>Подробней</summary>

  Скрипт остановит obfuscator и WireGuard, удалит интерфейс, бинарники, конфигурационные файлы и init-скрипт / systemd сервис.

  **Keenetic/Netcraze:** удаление интерфейсов через RCI API, сохранение конфигурации роутера
  **OpenWrt/ImmortalWrt:** удаление через UCI, firewall зоны `phobos`, сохранение конфигурации роутера
  **Linux:** удаление `/usr/local/bin/wg-obfuscator`, `/opt/Phobos`, `/etc/wireguard/phobos.conf`
</details>

## Совместимость и поддерживаемые платформы

### Сервер (VPS)
Протестированно и рекомендуется к использованию на **Ubuntu 20/22/24.04**.
Желательна установка на **чистый VPS** без предварительно установленных сервисов или конфигураций.
> Совместимость с другими дистрибутивами Linux и сторонними сервисами **не проверялась**.

### Клиенты

**Роутеры:**
- **Keenetic** (все модели с Entware) - mipsel, aarch64, mips
- **Netcraze** (устройства Keenetic под другой маркой) - mipsel, aarch64, mips
- **OpenWrt/LEDE** - mipsel, mips, aarch64, armv7, x86_64
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
