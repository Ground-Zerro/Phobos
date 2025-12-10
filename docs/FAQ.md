# Phobos - Часто задаваемые вопросы (FAQ)

## Общие вопросы

### Что такое Phobos?

Phobos - это система автоматизации развертывания WireGuard VPN с обфускацией трафика через wg-obfuscator. Она упрощает установку обфусцированного WireGuard подключения на роутеры Keenetic и OpenWrt до одной команды.

### Какие порты использует Phobos?

Phobos использует интеллектуальную систему генерации портов:
- **Obfuscator UDP порт:** 100-700 (случайный, исключая IANA зарезервированные порты)
- **HTTP сервер TCP порт:** 100-700 (случайный, не совпадающий с obfuscator портом)
- **WireGuard порт:** 51820 (localhost only, не доступен извне)

Система автоматически исключает:
- IANA зарезервированные порты (SSH, HTTP, DNS и т.д.)
- Часто используемые порты (888, 8080, 8888 и др.)
- Уже занятые порты (проверка через ss/netstat)

### Зачем нужны curl и jq на роутере?

**curl** - утилита для загрузки файлов из интернета. Необходима для:
- Скачивания установочных пакетов Phobos
- Работы с HTTP API

**jq** - утилита для корректного парсинга JSON. Необходима на роутерах Keenetic для:
- Работы с RCI API роутера Keenetic
- Автоматической настройки WireGuard интерфейсов
- Проверки состояния интерфейсов в health-check
- Удаления интерфейсов через uninstall скрипт

Обе утилиты устанавливаются автоматически при развертывании Phobos на роутере через opkg.

### Что используется для настройки OpenWrt?

На роутерах OpenWrt используется UCI (Unified Configuration Interface) - встроенная система конфигурации OpenWrt. WireGuard настраивается через команды `uci` без необходимости в дополнительных утилитах парсинга.

### Зачем нужна обфускация WireGuard?

WireGuard имеет характерный паттерн трафика, который может быть обнаружен системами DPI (Deep Packet Inspection) и заблокирован. wg-obfuscator скрывает трафик WireGuard, делая его похожим на обычный UDP трафик.

### Какие роутеры поддерживаются?

Phobos поддерживает две основные платформы:

#### Keenetic (все модели с Entware)
- **MIPSEL (Little Endian):** Giga (KN-1010/1011), Ultra (KN-1810), Viva (KN-1910/1912), Extra (KN-1710/1711/1712), City (KN-1510/1511), Start (KN-1110), Lite (KN-1310/1311), 4G (KN-1210/1211), Omni (KN-1410), Air (KN-1610), Air Primo (KN-1611), Mirand (KN-2010), Zyx (KN-2110), Musubi (KN-2210), Grid (KN-2410), Wave (KN-2510), Sky (KN-2610), Pro (KN-2810), Combo (KN-2910), Spiner (KN-3010), Doble (KN-3111), Doble Plus (KN-3112), Station (KN-3210) - первые версии, Cloud (KN-3510) - первые версии, Hurricane (KN-4010) - первые версии, Tornado (KN-4110) - первые версии и др.
- **ARM64 (AArch64):** Peak (KN-2710), Titan (KN-1920/1921), Hero 4G (KN-2310), Hopper (KN-3810), Play (KN-3110), Station (KN-3210) - более поздние версии, Omnia (KN-3310), Giant (KN-3410), Cloud (KN-3510) - более поздние версии, Link (KN-3610), Anchor (KN-3710), Arrow (KN-3910), Hurricane (KN-4010) - более поздние версии, Tornado (KN-4110) - более поздние версии, Hurricane II (KN-4210), Tornado II (KN-4310), Hurricane III (KN-4410), Tornado III (KN-4510), Magic (KN-4610), Switch (KN-1420), Switch 16 (KN-1421), XXL (KN-4710), Grand (KN-4810), Zyxel (KN-4910), Park (KN-5010), Lette (KN-5110)
- **MIPS (Big Endian):** Некоторые ранние версии моделей (до 2015 года), отдельные экземпляры старых моделей

#### OpenWrt/LEDE (все модели)
- **MIPSEL (Little Endian):** Большинство бюджетных роутеров TP-Link, Xiaomi Mi Router 3, Xiaomi Mi Router 4A
- **ARM64 (AArch64):** Современные роутеры (Linksys WRT32X, Netgear Nighthawk X4S R7800, Turris Omnia, NanoPi R2S/R4S)
- **MIPS (Big Endian):** Старые модели TP-Link (WDR3600/4300), D-Link DIR-825
- **ARMv7:** GL.iNet GL-MT300N-V2, Raspberry Pi 2/3, Banana Pi
- **x86_64:** PC-based роутеры, виртуальные машины, mini-PC

### Нужно ли устанавливать WireGuard на роутер?

**Для Keenetic:** Нет! WireGuard встроен в прошивку Keenetic. Phobos устанавливает только obfuscator.

**Для OpenWrt:** WireGuard устанавливается автоматически скриптом установки Phobos (пакеты kmod-wireguard, wireguard-tools, luci-app-wireguard).

## Установка

### Что делать, если Entware не установлен на Keenetic?

Обратиться к [официальному роководству по установке](https://help.keenetic.com/hc/ru/articles/360021214160-Установка-системы-пакетов-репозитория-Entware-на-USB-накопитель)

### Требуется ли Entware на OpenWrt?

Нет, OpenWrt использует собственный менеджер пакетов opkg. Все необходимые пакеты устанавливаются через opkg.

### Ошибка "command not found: curl" или "command not found: jq"

**В современных версиях Phobos** эти зависимости устанавливаются автоматически при развертывании.

Если по какой-то причине автоматическая установка не сработала:

**Для Keenetic (Entware):**
```bash
opkg update
opkg install curl jq
```

curl необходим для загрузки файлов, jq требуется для корректного парсинга JSON при работе с RCI API роутера Keenetic.

**Для OpenWrt:**
```bash
opkg update
opkg install curl jq
```

curl необходим для загрузки файлов, jq используется для парсинга JSON (устанавливается автоматически).

### Ошибка "tar: invalid option"

Используйте busybox tar:
```bash
busybox tar xzf phobos-client.tar.gz
```

### Недостаточно места на USB

Проверьте свободное место:
```bash
df -h
```

Минимум 5 MB требуется. Очистите ненужные файлы или используйте накопитель большего объема.

## Настройка

### Как изменить MTU в WireGuard?

**Для Keenetic:**
В веб-панели Keenetic при редактировании WireGuard подключения установите MTU = 1420.

**Для OpenWrt:**
В веб-интерфейсе LuCI перейдите в Network → Interfaces → phobos_wg → Advanced Settings → MTU = 1420.

Или через командную строку:
```bash
uci set network.phobos_wg.mtu='1420'
uci commit network
/etc/init.d/network reload
```

### Можно ли использовать несколько WireGuard подключений одновременно?

Да, но каждому потребуется свой obfuscator с уникальным локальным портом.

### Как настроить автоматическое подключение при загрузке?

**Для Keenetic:**
В веб-панели Keenetic включите опцию "Автоматическое подключение" для WireGuard. Obfuscator запускается автоматически через init-скрипт.

**Для OpenWrt:**
WireGuard интерфейс настроен на автоматический запуск по умолчанию. Obfuscator запускается автоматически через init-скрипт `/etc/init.d/wg-obfuscator`.

### Как изменить порт obfuscator на клиенте?

**Для Keenetic:**
Редактируйте `/opt/etc/Phobos/wg-obfuscator.conf`:
```ini
source-lport = 13255
```

После изменения перезапустите:
```bash
/opt/etc/init.d/S49wg-obfuscator restart
```

**Для OpenWrt:**
Редактируйте `/etc/Phobos/wg-obfuscator.conf`:
```ini
source-lport = 13255
```

После изменения перезапустите:
```bash
/etc/init.d/wg-obfuscator restart
```

## Работа системы

### Как проверить, что обфускация работает?

На сервере запустите tcpdump:
```bash
 tcpdump -i any -n udp and port <OBFUSCATOR_PORT>
```

Вы увидите UDP пакеты, но не характерный паттерн WireGuard handshake.

### Какая скорость достижима?

Зависит от:
- Производительности CPU роутера
- Скорости интернет-канала
- Загрузки сервера

Обфускация добавляет накладные расходы.

### Влияет ли obfuscator на задержку (ping)?

Да, но незначительно. Обычно добавляет 1-3ms.

### Сколько клиентов может обслуживать один сервер?

Технически WireGuard подсеть 10.25.0.0/16 поддерживает до 65534 клиентов.

Практические ограничения зависят от ресурсов сервера:
- VPS 1 core, 512 MB RAM: 10-20 активных клиентов
- VPS 2 core, 1 GB RAM: 50-100 активных клиентов
- VPS 4+ cores, 4 GB+ RAM: 200+ активных клиентов

### Как долго действителен установочный токен?

По умолчанию токен действителен 1 час (3600 секунд). Это значение хранится в параметре TOKEN_TTL в файле /opt/Phobos/server/server.env.

Срок действия можно указать при генерации установочной команды:

```bash
/opt/Phobos/repo/server/scripts/vps-generate-install-command.sh <client_name> [ttl_seconds]
```

Пример для токена на 24 часа:
```bash
/opt/Phobos/repo/server/scripts/vps-generate-install-command.sh client1 86400
```

## Безопасность

### Безопасна ли обфускация?

Obfuscator - это прокси-слой поверх WireGuard. Сама криптография WireGuard не изменяется. Безопасность остается на том же уровне.

### Можно ли перехватить ключи обфускации?

Ключ obfuscator передается через установочный пакет. Используйте безопасные каналы (HTTPS, SSH, SCP) для передачи пакетов клиентам.

### Нужно ли менять ключи obfuscator?

Рекомендуется периодически (раз в 3-6 месяцев) для усиления безопасности. При смене ключа нужно обновить конфигурацию на всех клиентах.

### Логируется ли трафик?

По умолчанию:
- WireGuard: не логирует трафик, только handshake
- wg-obfuscator: не логирует трафик
- Системные логи: только служебная информация (запуск/остановка)

## Решение проблем

### Obfuscator запускается, но WireGuard не подключается

1. Проверьте endpoint в конфигурации WireGuard (должен быть 127.0.0.1:13255)
2. Убедитесь, что obfuscator слушает порт 13255
3. Проверьте, что ключ obfuscator одинаковый на сервере и клиенте

### Подключение разрывается каждые несколько минут

1. Включите PersistentKeepalive в WireGuard (25 секунд)
2. Проверьте стабильность интернет-соединения роутера
3. Убедитесь, что роутер не перегружен (CPU < 90%)

### После перезагрузки роутера подключение не восстанавливается

**Для Keenetic:**
1. Проверьте автозапуск obfuscator:
```bash
ls -la /opt/etc/init.d/S49wg-obfuscator
```

2. Убедитесь, что WireGuard в Keenetic настроен на автоподключение

3. Проверьте порядок запуска: obfuscator должен запускаться ДО WireGuard

**Для OpenWrt:**
1. Проверьте автозапуск obfuscator:
```bash
ls -la /etc/init.d/wg-obfuscator
/etc/init.d/wg-obfuscator enabled && echo "Enabled" || echo "Disabled"
```

2. Проверьте автозапуск WireGuard интерфейса:
```bash
uci get network.phobos_wg.auto
```

3. Если автозапуск отключен:
```bash
/etc/init.d/wg-obfuscator enable
uci set network.phobos_wg.auto='1'
uci commit network
```

### Клиент не может подключиться после смены порта на сервере

Администратор должен:
1. Сгенерировать новую конфигурацию для клиента
2. Передать обновленный файл wg-obfuscator.conf

**Клиент на Keenetic:**
1. Заменить файл `/opt/etc/Phobos/wg-obfuscator.conf`
2. Перезапустить obfuscator:
```bash
/opt/etc/init.d/S49wg-obfuscator restart
```

**Клиент на OpenWrt:**
1. Заменить файл `/etc/Phobos/wg-obfuscator.conf`
2. Перезапустить obfuscator:
```bash
/etc/init.d/wg-obfuscator restart
```

### Ошибка "Address already in use"

Порт занят другим процессом. Найдите процесс:
```bash
netstat -ulnp | grep 13255
```

Остановите конфликтующий процесс или измените порт в конфигурации.

## Мониторинг

### Как проверить статус подключения?

**На клиенте Keenetic:**
```bash
/opt/etc/Phobos/health-check.sh
ping 10.25.0.1
```

**На клиенте OpenWrt:**
```bash
/etc/Phobos/health-check.sh
ping 10.25.0.1
```

**На клиенте Linux:**
```bash
/opt/Phobos/health-check.sh
ping 10.25.0.1
```

Скрипт покажет:
- Статус wg-obfuscator
- Все WireGuard интерфейсы
- Внешний IP для активных туннелей
- Состояние сетевого подключения

**На сервере:**
```bash
phobos  # выбрать "Мониторинг клиентов"
wg show
```

### Как посмотреть статистику трафика?

**На сервере:**
```bash
wg show wg0 transfer
```

**На клиенте Keenetic:**
Веб-панель → "Интернет" → "Другие подключения" → "WireGuard"

**На клиенте OpenWrt:**
Веб-интерфейс LuCI → Network → Interfaces → phobos_wg → Status

Или через командную строку:
```bash
wg show phobos_wg
```

### Как узнать, когда клиент последний раз подключался?

На сервере:
```bash
 wg show wg0 latest-handshakes
```

Или используйте скрипт мониторинга:
```bash
 /root/server/scripts/vps-monitor-clients.sh
```

## Обслуживание

### Как часто нужно обновлять wg-obfuscator?

Следите за релизами на https://github.com/ClusterM/wg-obfuscator. При наличии критичных обновлений рекомендуется обновить в течение месяца.

### Как сделать резервную копию конфигурации?

**На клиенте Keenetic:**
```bash
tar czf phobos-backup.tar.gz /opt/etc/Phobos /opt/etc/init.d/S49wg-obfuscator
```

**На клиенте OpenWrt:**
```bash
tar czf phobos-backup.tar.gz /etc/Phobos /etc/init.d/wg-obfuscator
```

**На сервере:**
В меню `Phobos` "Системные функции" → "Резервное копирование конфигураций"

или вручную:
```bash
 tar czf phobos-backup-$(date +%Y%m%d).tar.gz /opt/Phobos /etc/wireguard/wg0.conf
```

### Как восстановить из резервной копии?

**На сервере:**
В меню `phobos` "Системные функции" → "Резервное копирование конфигураций"

или вручную:
```bash
tar xzf phobos-backup.tar.gz -C /
systemctl restart wg-quick@wg0
```

**На клиенте Keenetic:**
```bash
tar xzf phobos-backup.tar.gz -C /
/opt/etc/init.d/S49wg-obfuscator restart
```

**На клиенте OpenWrt:**
```bash
tar xzf phobos-backup.tar.gz -C /
/etc/init.d/wg-obfuscator restart
/etc/init.d/network reload
```

### Нужно ли чистить логи?

Phobos не создает объемных логов. Системные логи управляются journald/syslog и ротируются автоматически.

## Производительность

### Как оптимизировать скорость?

1. Используйте MTU = 1420
2. Используйте современный роутер с ARM процессором
3. Выберите VPS ближе географически

### Влияет ли количество peers на производительность?

На клиенте - нет (только одно подключение).
На сервере - да, каждый peer добавляет нагрузку. При >50 peers рекомендуется мониторить CPU.

## Совместимость

### Совместимо ли с другими VPN?

Да, Phobos может работать одновременно с другими VPN на роутере (L2TP, PPTP, OpenVPN и др.).

### Работает ли с IPv6?

Да! Phobos автоматически определяет наличие IPv6 на VPS сервере с двойной проверкой:
- Проверяет доступность IPv6 интерфейса
- Запрашивает публичный IPv6 через несколько сервисов
- Перекрестно проверяет результаты для достоверности
- При наличии IPv6 настраивает dual-stack режим (IPv4 + IPv6)

WireGuard автоматически получает конфигурацию для обоих протоколов. `wg-obfuscator` работает прозрачно поверх IPv4/IPv6.

### Можно ли использовать на мобильных устройствах?

Напрямую - нет, скрипты оптимизированы для роутеров Keenetic и OpenWrt. Но можно:
1. Настроить `obfuscator` на мобильном устройстве вручную
2. Подключаться через роутер с Phobos (рекомендуется)

### Работает ли за CGNAT?

Да, клиенты могут быть за CGNAT. Сервер должен иметь публичный IP.

## Удаление

### Как полностью удалить Phobos?

**Для Keenetic:**
Выполните автоматический скрипт удаления:
```bash
/opt/etc/Phobos/phobos-uninstall.sh
```

Скрипт автоматически удалит все компоненты Phobos, включая WireGuard интерфейсы через RCI API.

**Для OpenWrt:**
Выполните автоматический скрипт удаления:
```bash
/etc/Phobos/phobos-uninstall.sh
```

**Для Linux:**
Выполните автоматический скрипт удаления:
```bash
/opt/Phobos/phobos-uninstall.sh
```

Скрипт автоматически удалит все компоненты Phobos, включая WireGuard интерфейс через UCI.

### Как удалить Phobos с сервера?

Для полного удаления:
```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh
```

Для удаления с сохранением резервной копии:
```bash
sudo /opt/Phobos/repo/server/scripts/vps-uninstall.sh --keep-data
```

### Что делать, если скрипт удаления не работает?

**На роутере Keenetic:**
1. Остановите obfuscator: `/opt/etc/init.d/S49wg-obfuscator stop`
2. Удалите файлы вручную: `rm -rf /opt/etc/Phobos /opt/bin/wg-obfuscator /opt/etc/init.d/S49wg-obfuscator`
3. Удалите WireGuard интерфейсы вручную через веб-панель Keenetic

**На роутере OpenWrt:**
1. Остановите obfuscator: `/etc/init.d/wg-obfuscator stop`
2. Удалите файлы вручную: `rm -rf /etc/Phobos /usr/bin/wg-obfuscator /etc/init.d/wg-obfuscator`
3. Удалите WireGuard интерфейс через UCI:
```bash
uci delete network.phobos_wg
uci delete firewall.phobos_zone
uci delete firewall.phobos_forwarding
uci commit
/etc/init.d/network reload
/etc/init.d/firewall reload
```

## Дополнительно

**Сервер:**
- `journalctl -u wg-obfuscator` - логи obfuscator
- `journalctl -u wg-quick@wg0` - логи WireGuard
- `/opt/Phobos/logs/cleanup.log` - логи очистки токенов
- `/opt/Phobos/logs/health-check.log` - логи health check

### Как связаться с разработчиками?

- GitHub Issues: https://github.com/Ground-Zerro/Phobos
- wg-obfuscator: https://github.com/ClusterM/wg-obfuscator

### Есть ли веб-панель управления?

Пока управление через интерактивное меню (`phobos`) и консольные скрипты.

### Что такое интерактивное меню управления?

Интерактивное меню (`phobos`) - это система управления, она предоставляет удобный интерфейс для:
- Управления сервисами (WireGuard, obfuscator, HTTP сервер)
- Управления клиентами (создание, удаление, пересоздание)
- Системных функций (бэкапы, очистка, мониторинг)
- Настройки параметров obfuscator

Для запуска используйте команду `phobos` на сервере.

### Как удалить клиента?

Клиента можно удалить через интерактивное меню (`phobos` → Управление клиентами → Удалить клиента)
или напрямую командой:
```bash
/root/server/scripts/vps-client-remove.sh <client_name>
```

### Как пересоздать конфигурацию клиента?

Через интерактивное меню: ` phobos` → Управление клиентами → Пересоздать конфигурацию клиента

Или напрямую: удалите старого клиента и создайте заново:
```bash
 /root/server/scripts/vps-client-remove.sh <client_name>
 /root/server/scripts/vps-client-add.sh <client_name>
```

### Могу ли я помочь проекту?

Да!
- Тестирование на разных моделях Keenetic
- Улучшение документации
- Перевод на другие языки
- Pull requests с улучшениями

### Где получить помощь?

1. Проверьте эту FAQ
2. Изучите README-server.md и README-client.md
3. Создайте Issue на GitHub с подробным описанием проблемы
4. Приложите логи и вывод скриптов диагностики
