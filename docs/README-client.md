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

Этот документ описывает установку клиентской части Phobos на роутеры Keenetic (с Entware) и OpenWrt. Установка занимает 5-10 минут.

### Что будет установлено

**Для Keenetic:**
- curl, jq - утилиты для загрузки файлов и парсинга JSON (автоматически через opkg)
- wg-obfuscator - программа для обфускации WireGuard трафика
- Автозапуск obfuscator через init-скрипт
- Конфигурационные файлы в /opt/etc/Phobos/
- Скрипты обслуживания (health-check, uninstall)

**Важно:** WireGuard встроен в прошивку Keenetic и не требует установки!

**Для OpenWrt:**
- WireGuard пакеты (kmod-wireguard, wireguard-tools, luci-app-wireguard)
- wg-obfuscator - программа для обфускации WireGuard трафика
- Автозапуск obfuscator через init-скрипт
- Конфигурационные файлы в /etc/Phobos/
- Скрипты обслуживания (health-check, uninstall)

## Требования

### Роутер Keenetic

- Модель: Keenetic с поддержкой компонентов
- Свободная память: 5+ MB
- Entware: должен быть установлен

### Роутер OpenWrt

- Модель: любой роутер с OpenWrt/LEDE
- Свободная память: 10+ MB
- OpenWrt версия: 19.07+

### Поддерживаемые архитектуры

**Keenetic:**
- **MIPSEL** (Little Endian) - большинство моделей Keenetic
  - Giga (KN-1010/1011), Ultra (KN-1810), Viva (KN-1910/1912), Extra (KN-1710/1711/1712), City (KN-1510/1511), Start (KN-1110), Lite (KN-1310/1311), 4G (KN-1210/1211), Omni (KN-1410), Air (KN-1610), Air Primo (KN-1611), Mirand (KN-2010), Zyx (KN-2110), Musubi (KN-2210), Grid (KN-2410), Wave (KN-2510), Sky (KN-2610), Pro (KN-2810), Combo (KN-2910), Spiner (KN-3010), Doble (KN-3111), Doble Plus (KN-3112), Station (KN-3210) - первые версии, Cloud (KN-3510) - первые версии, Hurricane (KN-4010) - первые версии, Tornado (KN-4110) - первые версии и др.
- **ARM64** (AArch64) - современные мощные модели
  - Peak (KN-2710), Titan (KN-1920/1921), Hero 4G (KN-2310), Hopper (KN-3810), Play (KN-3110), Station (KN-3210) - более поздние версии, Omnia (KN-3310), Giant (KN-3410), Cloud (KN-3510) - более поздние версии, Link (KN-3610), Anchor (KN-3710), Arrow (KN-3910), Hurricane (KN-4010) - более поздние версии, Tornado (KN-4110) - более поздние версии, Hurricane II (KN-4210), Tornado II (KN-4310), Hurricane III (KN-4410), Tornado III (KN-4510), Magic (KN-4610), Switch (KN-1420), Switch 16 (KN-1421), XXL (KN-4710), Grand (KN-4810), Zyxel (KN-4910), Park (KN-5010), Lette (KN-5110)
- **MIPS** (Big Endian) - редкие старые модели
  - Некоторые ранние версии моделей (до 2015 года), отдельные экземпляры старых моделей

**OpenWrt:**
- **MIPSEL** (Little Endian) - большинство бюджетных роутеров TP-Link, Xiaomi Mi Router 3, Xiaomi Mi Router 4A
- **ARM64** (AArch64) - современные роутеры (Linksys WRT32X, Netgear Nighthawk X4S R7800, Turris Omnia, NanoPi R2S/R4S)
- **MIPS** (Big Endian) - старые модели TP-Link (WDR3600/4300), D-Link DIR-825
- **ARMv7** - GL.iNet GL-MT300N-V2, Raspberry Pi 2/3, Banana Pi
- **x86_64** - PC-based роутеры, виртуальные машины, mini-PC

## Подготовка роутера

### Keenetic

#### 1. Установка Entware (если не установлен)

Обратиться к [официальному роководству по установке](https://help.keenetic.com/hc/ru/articles/360021214160-Установка-системы-пакетов-репозитория-Entware-на-USB-накопитель)

#### 2. Подключение по SSH

```bash
ssh -p 222 root@<router_ip>
```

Введите пароль при запросе.

#### 3. Проверка Entware

```bash
opkg --version
```

Если команда не найдена, Entware не установлен.

### OpenWrt

#### 1. Подключение по SSH

```bash
ssh root@<router_ip>
```

Введите пароль при запросе.

#### 2. Проверка версии OpenWrt

```bash
cat /etc/openwrt_release
```

Рекомендуется OpenWrt 19.07 или новее.

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

Выполните команду на роутере через SSH.

**Для Keenetic скрипт автоматически:**
1. Установит недостающие зависимости (curl, jq) через opkg
2. Загрузит установочный пакет
3. Определит архитектуру роутера
4. Установит правильный бинарник wg-obfuscator
5. Настроит автозапуск obfuscator
6. Настроит WireGuard через RCI API (с использованием jq для парсинга JSON)
7. Активирует подключение и проверит создание интерфейса
8. Развернет скрипты health-check и uninstall

**Для OpenWrt скрипт автоматически:**
1. Установит недостающие зависимости (curl, jq) через opkg
2. Установит WireGuard пакеты (kmod-wireguard, wireguard-tools, luci-app-wireguard)
3. Загрузит установочный пакет
4. Определит архитектуру роутера
5. Установит правильный бинарник wg-obfuscator
6. Настроит автозапуск obfuscator
7. Настроит WireGuard через UCI
8. Создаст интерфейс "phobos_wg" и firewall зону "phobos"
9. Активирует подключение
10. Развернет скрипты health-check и uninstall

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

Скрипт установки определит платформу (Keenetic или OpenWrt) автоматически и выполнит:
- Определение архитектуры роутера
- Установку правильного бинарника wg-obfuscator
- Создание конфигурационных файлов
- Настройку автозапуска через init-скрипт
- Автоматическую настройку WireGuard (RCI API для Keenetic, UCI для OpenWrt)

## Настройка WireGuard

### Автоматическая настройка (рекомендуется)

При установке через скрипт WireGuard настраивается автоматически.

**Для Keenetic через RCI API:**

- Создаётся интерфейс с именем "Phobos-{client_name}"
- Настраиваются все параметры (IP, ключи, endpoint)
- Активируется подключение
- Проверяется handshake с сервером

**Для OpenWrt через UCI:**

- Создаётся интерфейс "phobos_wg"
- Настраиваются все параметры (IP, ключи, endpoint)
- Создаётся firewall зона "phobos" с разрешением форвардинга в WAN
- Активируется подключение
- Проверяется handshake с сервером

**Проверка результата:**

Если настройка прошла успешно, вы увидите сообщение:
```
✓ WireGuard успешно настроен и подключен!
```

### Ручная настройка (fallback)

#### Для Keenetic

Если RCI API недоступен (старая версия Keenetic OS < 4.0) или автоматическая настройка не удалась:

**Импорт конфигурации вручную:**

1. Откройте веб-панель Keenetic (http://192.168.1.1)
2. Перейдите в "Интернет" → "Другие подключения" → "WireGuard"
3. Нажмите "Загрузить из файла"

**Получение файла конфигурации:**

Вариант A - Через SCP:
```bash
scp root@<router_ip>:/opt/etc/Phobos/<client_name>.conf .
```

Вариант B - Копирование содержимого:
```bash
ssh root@<router_ip>
cat /opt/etc/Phobos/<client_name>.conf
```

**Активация подключения:**

1. После импорта активируйте подключение WireGuard
2. Подождите 5-10 секунд
3. Проверьте статус в веб-панели (должно быть "Подключено")

#### Для OpenWrt

Автоматическая настройка через UCI обычно работает без проблем. При необходимости ручной настройки используйте веб-интерфейс LuCI:

**Ручная настройка через LuCI:**

1. Откройте LuCI (http://192.168.1.1)
2. Перейдите в Network → Interfaces → Add new interface
3. Имя: phobos_wg, Protocol: WireGuard VPN
4. Укажите параметры из файла `/etc/Phobos/<client_name>.conf`
5. Настройте firewall зону "phobos" с форвардингом в WAN

## Проверка работы

### Базовая проверка

**Для Keenetic:**
```bash
/opt/etc/Phobos/health-check.sh
```

**Для OpenWrt:**
```bash
/etc/Phobos/health-check.sh
```

**Для Linux:**
```bash
/opt/Phobos/health-check.sh
```

Скрипт проверит:
- Статус wg-obfuscator
- Конфигурационные файлы
- WireGuard интерфейсы (jq для Keenetic, UCI для OpenWrt)
- Внешний IP для всех активных WireGuard туннелей
- Сетевое подключение

**Пример вывода для активных туннелей:**
```
==> Проверка WireGuard
✓ WireGuard интерфейсов: 2
  └─ Детали интерфейсов:
    Wireguard0: Phobos-client1 - up (IP: 94.183.235.179)
    Wireguard1: Another-VPN - down
```

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
ping -c 3 10.25.0.1
```

Должен отвечать сервер через туннель.

### Проверка WireGuard

**Для Keenetic (веб-панель):**
- Перейдите в "Интернет" → "WireGuard"
- Проверьте статус подключения
- Должно быть "Подключено" с зеленым индикатором
- Интерфейс будет называться "Phobos-{client_name}" (при автоматической настройке)

**Для OpenWrt (LuCI):**
- Перейдите в Network → Interfaces
- Проверьте статус phobos_wg
- Должно быть "Connected" с зеленым индикатором
- Или через командную строку: `ifconfig phobos_wg`

**Для Linux (systemd):**
```bash
systemctl status wg-quick@phobos
wg show phobos
ip addr show phobos
```

VPN настроен как запасной интерфейс и не перехватывает системный трафик автоматически.

Для направления трафика через VPN используйте одну из опций:

**Опция 1: Временно направить весь трафик через VPN**
```bash
ip route add default dev phobos metric 100
```
Для отмены:
```bash
ip route del default dev phobos metric 100
```

**Опция 2: Направить трафик конкретного приложения через VPN**
```bash
ip netns add vpn
ip netns exec vpn ip link set lo up
ip link set phobos netns vpn
ip netns exec vpn wg-quick up phobos
ip netns exec vpn firefox
```

**Опция 3: Постоянно направлять весь трафик через VPN**
Отредактируйте `/etc/wireguard/phobos.conf`, удалите строку `Table = off` и перезапустите:
```bash
systemctl restart wg-quick@phobos
```

## Обслуживание

### Перезапуск obfuscator

**Для Keenetic:**
```bash
/opt/etc/init.d/S49wg-obfuscator restart
```

**Для OpenWrt:**
```bash
/etc/init.d/wg-obfuscator restart
```

**Для Linux:**
```bash
systemctl restart phobos-obfuscator
systemctl restart wg-quick@phobos
```

### Остановка obfuscator

**Для Keenetic:**
```bash
/opt/etc/init.d/S49wg-obfuscator stop
```

**Для OpenWrt:**
```bash
/etc/init.d/wg-obfuscator stop
```

**Для Linux:**
```bash
systemctl stop phobos-obfuscator
systemctl stop wg-quick@phobos
```

### Запуск obfuscator

**Для Keenetic:**
```bash
/opt/etc/init.d/S49wg-obfuscator start
```

**Для OpenWrt:**
```bash
/etc/init.d/wg-obfuscator start
```

**Для Linux:**
```bash
systemctl start phobos-obfuscator
systemctl start wg-quick@phobos
```

### Проверка статуса

**Для Keenetic:**
```bash
/opt/etc/init.d/S49wg-obfuscator status
```

**Для OpenWrt:**
```bash
/etc/init.d/wg-obfuscator status
```

**Для Linux:**
```bash
systemctl status phobos-obfuscator
systemctl status wg-quick@phobos
journalctl -u phobos-obfuscator -f
```

### Обновление конфигурации

Если администратор изменил настройки сервера:

**Для Keenetic:**
```bash
scp new-wg-obfuscator.conf root@<router_ip>:/opt/etc/Phobos/wg-obfuscator.conf
/opt/etc/init.d/S49wg-obfuscator restart
```

**Для OpenWrt:**
```bash
scp new-wg-obfuscator.conf root@<router_ip>:/etc/Phobos/wg-obfuscator.conf
/etc/init.d/wg-obfuscator restart
```

### Удаление

**Для Keenetic:**

Используйте автоматический скрипт удаления:
```bash
/opt/etc/Phobos/phobos-uninstall.sh
```

Скрипт автоматически:
- Остановит wg-obfuscator
- Найдет и удалит все WireGuard интерфейсы Phobos через RCI API
- Удалит бинарник (/opt/bin/wg-obfuscator)
- Удалит init-скрипт (/opt/etc/init.d/S49wg-obfuscator)
- Удалит конфигурационные файлы (/opt/etc/Phobos)
- Сохранит конфигурацию роутера

Ручное удаление (если скрипт недоступен):
```bash
/opt/etc/init.d/S49wg-obfuscator stop
rm -f /opt/bin/wg-obfuscator
rm -f /opt/etc/init.d/S49wg-obfuscator
rm -rf /opt/etc/Phobos
```
Затем удалите WireGuard подключения вручную через веб-панель Keenetic.

**Для OpenWrt:**

Используйте автоматический скрипт удаления:
```bash
/etc/Phobos/phobos-uninstall.sh
```

**Для Linux:**

Используйте автоматический скрипт удаления:
```bash
/opt/Phobos/phobos-uninstall.sh
```

Скрипт автоматически:
- Остановит wg-obfuscator
- Удалит WireGuard интерфейс и firewall зону через UCI
- Удалит бинарник (/usr/bin/wg-obfuscator)
- Удалит init-скрипт (/etc/init.d/wg-obfuscator)
- Удалит конфигурационные файлы (/etc/Phobos)
- Сохранит конфигурацию роутера

Ручное удаление (если скрипт недоступен):
```bash
/etc/init.d/wg-obfuscator stop
rm -f /usr/bin/wg-obfuscator
rm -f /etc/init.d/wg-obfuscator
rm -rf /etc/Phobos
uci delete network.phobos_wg
uci delete firewall.phobos_zone
uci delete firewall.phobos_forwarding
uci commit
/etc/init.d/network reload
/etc/init.d/firewall reload
```

## Решение проблем

### Obfuscator не запускается

**Для Keenetic:**
```bash
file /opt/bin/wg-obfuscator
/opt/bin/wg-obfuscator -h
/opt/bin/wg-obfuscator -c /opt/etc/Phobos/wg-obfuscator.conf
```

**Для OpenWrt:**
```bash
file /usr/bin/wg-obfuscator
/usr/bin/wg-obfuscator -h
/usr/bin/wg-obfuscator -c /etc/Phobos/wg-obfuscator.conf
```

### WireGuard не подключается

1. Проверьте, что obfuscator запущен:
```bash
ps | grep wg-obfuscator
```

2. Проверьте, что WireGuard endpoint указывает на 127.0.0.1:13255

3. Перезапустите WireGuard:
   - **Keenetic:** в веб-панели Keenetic
   - **OpenWrt:** `ifdown phobos_wg && ifup phobos_wg`

4. Проверьте доступность сервера:
```bash
ping <server_public_ip>
```

### Нет доступа в интернет через туннель

1. Проверьте маршруты:
   - **Keenetic:** в веб-панели Keenetic
   - **OpenWrt:** `ip route` или LuCI → Network → Routes

2. Убедитесь, что WireGuard подключение активно

3. Проверьте DNS:
```bash
nslookup google.com
```

### Obfuscator падает после перезагрузки

**Для Keenetic:**
```bash
ls -la /opt/etc/init.d/S49wg-obfuscator
```

**Для OpenWrt:**
```bash
ls -la /etc/init.d/wg-obfuscator
/etc/init.d/wg-obfuscator enabled && echo "Enabled" || echo "Disabled"
```

Файл должен существовать и иметь права на выполнение. Для OpenWrt также убедитесь, что сервис включен в автозапуск.

## Структура файлов

**Для Keenetic:**
```
/opt/bin/wg-obfuscator                      - Бинарник obfuscator
/opt/etc/Phobos/
├── <client_name>.conf                      - Конфиг WireGuard (fallback для ручного импорта)
├── wg-obfuscator.conf                      - Конфиг obfuscator
├── health-check.sh                         - Скрипт проверки состояния системы
└── phobos-uninstall.sh                     - Скрипт удаления Phobos
/opt/etc/init.d/S49wg-obfuscator            - Init-скрипт автозапуска obfuscator
```

**Для OpenWrt:**
```
/usr/bin/wg-obfuscator                      - Бинарник obfuscator
/etc/Phobos/
├── <client_name>.conf                      - Конфиг WireGuard (fallback для ручной настройки)
├── wg-obfuscator.conf                      - Конфиг obfuscator
├── health-check.sh                         - Скрипт проверки состояния системы
└── phobos-uninstall.sh                     - Скрипт удаления Phobos
/etc/init.d/wg-obfuscator                   - Init-скрипт автозапуска obfuscator
```

**Для Linux:**
```
/usr/local/bin/wg-obfuscator                - Бинарник obfuscator
/opt/Phobos/
├── <client_name>.conf                      - Исходный конфиг WireGuard
├── wg-obfuscator.conf                      - Конфиг obfuscator
├── health-check.sh                         - Скрипт проверки состояния системы
└── phobos-uninstall.sh                     - Скрипт удаления Phobos
/etc/wireguard/phobos.conf                  - Конфиг WireGuard для systemd (интерфейс: phobos)
/etc/systemd/system/phobos-obfuscator.service - Systemd service obfuscator
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
