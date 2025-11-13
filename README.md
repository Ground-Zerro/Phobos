# Phobos

Автоматизация развертывания защищенного WireGuard с обфускацией трафика через `wg-obfuscator`.

## Описание

**Phobos** автоматизирует настройку обфусцированного WireGuard соединения между VPS сервером и клиентскими роутерами (Keenetic, OpenWrt).

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

### 2. Установка на роутер

#### Keenetic (Entware)

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

## Интерактивное меню управления

Система включает интерактивное меню управления.

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

### Удаление с роутера

#### Keenetic

Для полного удаления Phobos с роутера Keenetic:

```bash
/opt/etc/Phobos/router-uninstall.sh
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
/etc/Phobos/router-uninstall.sh
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

## Совместимость и рекомендации по установке

Протестированно и рекомендуется к использованию на **Ubuntu 20.04** и **Ubuntu 22.04**.  
Желательна установка на **чистый VPS** без предварительно установленных сервисов или конфигураций.
> Совместимость с другими дистрибутивами Linux и сторонними сервисами **не проверялась**.

## License

This project is licensed under GPL-3.0.
See the [LICENSE](./LICENSE) file for full terms.

## Благодарности

- [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) — инструмент обфускации WireGuard трафика /[Поблагадарить Алексея и поддержать его разработку](https://boosty.to/cluster)/
- [WireGuard](https://www.wireguard.com/) — современный VPN протокол

## Поддержка

**Угостить автора чашечкой какао можно на** [Boosty](https://boosty.to/ground_zerro) ❤️
