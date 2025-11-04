# Phobos Client - Руководство пользователя

## Содержание

- [Введение](#введение)
- [Требования](#требования)
- [Подготовка роутера](#подготовка-роутера)
- [Установка](#установка)
- [Настройка WireGuard](#настройка-wireguard)
- [Проверка работы](#проверка-работы)
- [Обслуживание](#обслуживание)
- [Решение проблем](#решение-проблем)
- [Совместимость с обновлениями](#совместимость-с-обновлениями)

## Введение

Этот документ описывает установку клиентской части Phobos на роутер Keenetic с Entware. Установка занимает 5-10 минут.

### Что будет установлено

- wg-obfuscator - программа для обфускации WireGuard трафика
- Автозапуск obfuscator через init-скрипт
- Конфигурационные файлы в /opt/etc/Phobos/

**Важно:** WireGuard уже встроен в прошивку Keenetic и не требует установки!

## Требования

### Роутер

- Модель: Keenetic с поддержкой компонентов
- Свободная память: 5+ MB
- Entware: должен быть установлен

### Поддерживаемые архитектуры

- **MIPSEL** (Little Endian) - большинство моделей Keenetic
  - Giga (KN-1010/1011), Ultra (KN-1810), Viva (KN-1910/1912), Extra (KN-1710/1711/1712), City (KN-1510/1511), Start (KN-1110), Lite (KN-1310/1311), 4G (KN-1210/1211), Omni (KN-1410), Air (KN-1610), Air Primo (KN-1611), Mirand (KN-2010), Zyx (KN-2110), Musubi (KN-2210), Grid (KN-2410), Wave (KN-2510), Sky (KN-2610), Pro (KN-2810), Combo (KN-2910), Spiner (KN-3010), Doble (KN-3111), Doble Plus (KN-3112), Station (KN-3210) - первые версии, Cloud (KN-3510) - первые версии, Hurricane (KN-4010) - первые версии, Tornado (KN-4110) - первые версии и др.
- **ARM64** (AArch64) - современные мощные модели
  - Peak (KN-2710), Titan (KN-1920/1921), Hero 4G (KN-2310), Hopper (KN-3810), Play (KN-3110), Station (KN-3210) - более поздние версии, Omnia (KN-3310), Giant (KN-3410), Cloud (KN-3510) - более поздние версии, Link (KN-3610), Anchor (KN-3710), Arrow (KN-3910), Hurricane (KN-4010) - более поздние версии, Tornado (KN-4110) - более поздние версии, Hurricane II (KN-4210), Tornado II (KN-4310), Hurricane III (KN-4410), Tornado III (KN-4510), Magic (KN-4610), Switch (KN-1420), Switch 16 (KN-1421), XXL (KN-4710), Grand (KN-4810), Zyxel (KN-4910), Park (KN-5010), Lette (KN-5110)
- **MIPS** (Big Endian) - редкие старые модели
  - Некоторые ранние версии моделей (до 2015 года), отдельные экземпляры старых моделей

## Подготовка роутера

### 1. Установка Entware (если не установлен)

Обратиться к [официальному роководству по установке](https://help.keenetic.com/hc/ru/articles/360021214160-Установка-системы-пакетов-репозитория-Entware-на-USB-накопитель)

### 2. Подключение по SSH

```bash
ssh -p 222 root@<router_ip>
```

Введите пароль при запросе.

### 3. Проверка Entware

```bash
opkg --version
```

Если команда не найдена, Entware не установлен.

## Установка

### Метод 1: Автоматическая установка (рекомендуется)

Получите команду установки от администратора. Она выглядит так:

```bash
wget -O - http://<server_ip>:8080/init/<token>.sh | sh
```

или

```bash
curl -sL http://<server_ip>:8080/init/<token>.sh | sh
```

Выполните команду на роутере через SSH. Скрипт автоматически:
1. Загрузит установочный пакет
2. Определит архитектуру роутера
3. Установит правильный бинарник wg-obfuscator
4. Настроит автозапуск obfuscator
5. Настроит WireGuard через RCI API
6. Активирует подключение и проверит handshake

### Метод 2: Ручная установка

#### Шаг 1: Загрузка пакета

Получите файл `phobos-<client_name>.tar.gz` от администратора.

**Вариант A - через SCP:**
```bash
scp phobos-client1.tar.gz root@<router_ip>:/tmp/
```

**Вариант B - через wget:**
```bash
ssh root@<router_ip>
cd /tmp
wget http://<server_ip>:8080/packages/<token>/phobos-client1.tar.gz
```

#### Шаг 2: Определение архитектуры (опционально)

```bash
cd /tmp
tar xzf phobos-client1.tar.gz
cd phobos-client1
chmod +x detect-router-arch.sh
./detect-router-arch.sh
```

Скрипт покажет рекомендуемый бинарник для вашего роутера.

#### Шаг 3: Установка

```bash
chmod +x install-router.sh
./install-router.sh
```

Скрипт установки:
- Определит архитектуру автоматически
- Скопирует правильный бинарник в /opt/bin/
- Создаст конфигурационные файлы
- Настроит автозапуск через init-скрипт
- Автоматически настроит WireGuard через RCI API

## Настройка WireGuard

### Автоматическая настройка (рекомендуется)

При установке через скрипт WireGuard настраивается автоматически через RCI API:

- Создаётся интерфейс с именем "Phobos-{client_name}"
- Настраиваются все параметры (IP, ключи, endpoint)
- Активируется подключение
- Проверяется handshake с сервером

**Проверка результата:**

Если настройка прошла успешно, вы увидите сообщение:
```
✓ WireGuard успешно настроен и подключен!
```

### Ручная настройка (fallback)

Если RCI API недоступен (старая версия Keenetic OS < 4.0) или автоматическая настройка не удалась, потребуется ручной импорт через веб-панель Keenetic:

#### Импорт конфигурации вручную

1. Откройте веб-панель Keenetic (http://192.168.1.1)
2. Перейдите в "Интернет" → "Другие подключения" → "WireGuard"
3. Нажмите "Загрузить из файла"

#### Получение файла конфигурации

**Вариант A - Через SCP:**
```bash
scp root@<router_ip>:/opt/etc/Phobos/<client_name>.conf .
```

Затем загрузите файл через веб-панель.

**Вариант B - Копирование содержимого:**
```bash
ssh root@<router_ip>
cat /opt/etc/Phobos/<client_name>.conf
```

Скопируйте содержимое и вставьте в веб-панель.

#### Активация подключения

1. После импорта активируйте подключение WireGuard
2. Подождите 5-10 секунд
3. Проверьте статус в веб-панели (должно быть "Подключено")

## Проверка работы

### Базовая проверка

```bash
/opt/etc/Phobos/router-health-check.sh
```

Скрипт проверит:
- Статус wg-obfuscator
- Конфигурационные файлы
- WireGuard в Keenetic
- Сетевое подключение

### Ручная проверка

```bash
ps | grep wg-obfuscator
```

Процесс должен быть запущен.

```bash
netstat -ulnp | grep wg-obfuscator
```

Должен слушать UDP порт 13255 на 127.0.0.1.

```bash
ping -c 3 10.8.0.1
```

Должен отвечать сервер через туннель.

### Проверка WireGuard

**В веб-панели Keenetic:**
- Перейдите в "Интернет" → "WireGuard"
- Проверьте статус подключения
- Должно быть "Подключено" с зеленым индикатором
- Интерфейс будет называться "Phobos-{client_name}" (при автоматической настройке)

## Обслуживание

### Перезапуск obfuscator

```bash
/opt/etc/init.d/S49wg-obfuscator restart
```

### Остановка obfuscator

```bash
/opt/etc/init.d/S49wg-obfuscator stop
```

### Запуск obfuscator

```bash
/opt/etc/init.d/S49wg-obfuscator start
```

### Проверка статуса

```bash
/opt/etc/init.d/S49wg-obfuscator status
```

### Обновление конфигурации

Если администратор изменил настройки сервера:

1. Получите новую конфигурацию obfuscator
2. Замените файл:
```bash
scp new-wg-obfuscator.conf root@<router_ip>:/opt/etc/Phobos/wg-obfuscator.conf
/opt/etc/init.d/S49wg-obfuscator restart
```

### Удаление

```bash
/opt/etc/init.d/S49wg-obfuscator stop
rm -f /opt/bin/wg-obfuscator
rm -f /opt/etc/init.d/S49wg-obfuscator
rm -rf /opt/etc/Phobos
```

Затем удалите WireGuard подключение через веб-панель Keenetic.

## Решение проблем

### Obfuscator не запускается

**Проверка бинарника:**
```bash
file /opt/bin/wg-obfuscator
/opt/bin/wg-obfuscator -h
```

**Ручной запуск для отладки:**
```bash
/opt/bin/wg-obfuscator -c /opt/etc/Phobos/wg-obfuscator.conf
```

### WireGuard не подключается

1. Проверьте, что obfuscator запущен:
```bash
ps | grep wg-obfuscator
```

2. Проверьте, что WireGuard endpoint указывает на 127.0.0.1:13255

3. Перезапустите WireGuard в веб-панели Keenetic

4. Проверьте доступность сервера:
```bash
ping <server_public_ip>
```

### Нет доступа в интернет через туннель

1. Проверьте маршруты в веб-панели Keenetic
2. Убедитесь, что WireGuard подключение активно
3. Проверьте DNS:
```bash
nslookup google.com
```

### Obfuscator падает после перезагрузки

Проверьте автозапуск:
```bash
ls -la /opt/etc/init.d/S49wg-obfuscator
```

Файл должен существовать и иметь права на выполнение.

## Структура файлов

```
/opt/bin/wg-obfuscator                      - Бинарник obfuscator
/opt/etc/Phobos/
├── <client_name>.conf                      - Конфиг WireGuard (fallback для ручного импорта)
└── wg-obfuscator.conf                      - Конфиг obfuscator
/opt/etc/init.d/S49wg-obfuscator            - Init-скрипт автозапуска obfuscator
```

## Полезные команды

```bash
opkg list-installed                  # Установленные пакеты
ps | grep wg                         # Процессы WireGuard/obfuscator
netstat -ulnp                        # Открытые UDP порты
cat /proc/cpuinfo                    # Информация о процессоре
df -h                                # Свободное место на диске
uptime                               # Время работы и нагрузка
```
## Контакты и поддержка

По вопросам обращайтесь к администратору, который предоставил установочный пакет.

- GitHub: https://github.com/Ground-Zerro/Phobos
- Issues: https://github.com/Ground-Zerro/Phobos/issues
