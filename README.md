# Phobos

Автоматизация развертывания защищенного WireGuard VPN с обфускацией трафика через `wg-obfuscator`.

## Описание

**Phobos** автоматизирует настройку обфусцированного WireGuard соединения между VPS сервером и клиентскими роутерами (Entware).

### Ключевые особенности

- Случайная генерация UDP порта для obfuscator (10000-60000)
- Сборка wg-obfuscator из исходников с кросс-компиляцией для роутеров (mipsel, mips, aarch64)
- Автоматическое определение архитектуры роутера и выбор правильного бинарника
- Управление через итерактивное меню (VPS)

## Функции

### Интерактивное меню управления

Система включает интерактивное меню управления.

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
./server/scripts/vps-init-all.sh
```

### 2. Создание клиента

После установки лоступно интерактивное меню `phobos`. Запустите его командой:

```bash
phobos
```
и добавьте нового клиента.

Система:
- Создаст клиента с конфигурацией WireGuard
- Сгенерирует установочный пакет со всеми бинарниками
- Создаст одноразовую команду установки с токеном
- Выдаст готовую HTTP ссылку для роутера, например:

```bash
wget -O - http://100.100.100.101:8080/init/a1b2c3d4e5f6.sh | sh
```

### 3. Установка на роутер Keenetic (полностью автоматическая)

Отправьте ссылку клиенту, он выполняет ее на роутере в терминале:

```bash
wget -O - http://100.100.100.101:8080/init/a1b2c3d4e5f6.sh | sh
```

Скрипт:
- Скачает установочный пакет
- Определит архитектуру роутера
- Установит правильный бинарник wg-obfuscator
- Настроит автозапуск obfuscator
- Настроит WireGuard через RCI API
- Создаст интерфейс "Phobos-{client_name}"
- Активирует подключение
- Проверит handshake

## License

This project is licensed under a **Proprietary License**.  
See the [LICENSE](./LICENSE) file for full terms.

## External dependency: wg-obfuscator (GPL-3.0)

This repository provides a wrapper that automates configuration or invocation of `wg-obfuscator`.  
This project does NOT include, distribute, or modify `wg-obfuscator` source or binaries.

/* RU — для внутренней справки */
Этот проект содержит только обвязку. Бинарники/исходники `wg-obfuscator` не включены и не распространяются здесь.

## Благодарности

- [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) — инструмент обфускации WireGuard трафика /[Поблагадарить Алексея и поддержать его разработку](https://boosty.to/cluster)/
- [WireGuard](https://www.wireguard.com/) — современный VPN протокол

## Поддержка

**Угостить автора чашечкой какао можно на** [Boosty](https://boosty.to/ground_zerro) ❤️
