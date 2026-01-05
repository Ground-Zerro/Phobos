# Phobos - Руководство по устранению неполадок

## Быстрая диагностика

### Сервер

```bash
sudo /opt/Phobos/repo/server/scripts/vps-health-check.sh
sudo /opt/Phobos/repo/server/scripts/vps-monitor-clients.sh
```

### Клиент (роутер)

```bash
/opt/etc/Phobos/router-health-check.sh
```

## Распространенные проблемы

### 1. Клиент не может подключиться

#### Симптомы
- WireGuard показывает "Подключение..." но не подключается
- Нет трафика через туннель
- Ping 10.25.0.1 не работает

#### Диагностика

**Шаг 1: Проверка obfuscator на клиенте**
```bash
ps | grep wg-obfuscator
netstat -ulnp | grep 13255
```

Ожидаемый результат: процесс запущен, слушает 127.0.0.1:13255

**Шаг 2: Проверка obfuscator на сервере**
```bash
sudo systemctl status wg-obfuscator
sudo ss -ulnp | grep <OBFUSCATOR_PORT>
```

Ожидаемый результат: сервис active, слушает 0.0.0.0:<OBFUSCATOR_PORT>

**Шаг 3: Проверка WireGuard на сервере**
```bash
sudo wg show
```

Должен быть peer с public key клиента, но handshake = 0

**Шаг 4: Проверка ключей**
```bash
sudo cat /opt/Phobos/clients/<client_name>/wg-obfuscator.conf | grep "key ="
cat /opt/etc/Phobos/wg-obfuscator.conf | grep "key ="
```

Ключи должны совпадать!

**Шаг 5: Проверка портов**
```bash
cat /opt/etc/Phobos/wg-obfuscator.conf | grep "target ="
cat /opt/Phobos/server/server.env | grep "OBFUSCATOR_PORT"
```

target должен указывать на правильный порт сервера

#### Решение

**Если порт неправильный:**
Пересоздайте клиента или обновите конфигурацию вручную

**Если obfuscator не запущен:**
```bash
/opt/etc/init.d/S49wg-obfuscator start
```

### 2. Obfuscator не запускается

#### Симптомы
- Процесс wg-obfuscator отсутствует
- Init скрипт возвращает ошибку

#### Диагностика

**Проверка бинарника:**
```bash
file /opt/bin/wg-obfuscator
/opt/bin/wg-obfuscator -h
```

**Проверка архитектуры:**
```bash
uname -m
cat /proc/cpuinfo | head -20
```

**Ручной запуск для отладки:**
```bash
/opt/bin/wg-obfuscator -c /opt/etc/Phobos/wg-obfuscator.conf
```

#### Решение

**Ошибка "cannot execute binary file":**
Неправильная архитектура бинарника

```bash
cd /tmp/phobos-<client_name>
./detect-router-arch.sh

ARCH=$(uname -m)
if [[ "${ARCH}" == "mipsel" ]]; then
  cp bin/wg-obfuscator-mipsel /opt/bin/wg-obfuscator
elif [[ "${ARCH}" == "mips" ]]; then
  cp bin/wg-obfuscator-mips /opt/bin/wg-obfuscator
elif [[ "${ARCH}" == "aarch64" ]]; then
  cp bin/wg-obfuscator-aarch64 /opt/bin/wg-obfuscator
elif [[ "${ARCH}" == "armv7l" ]]; then
  cp bin/wg-obfuscator-armv7 /opt/bin/wg-obfuscator
fi

chmod +x /opt/bin/wg-obfuscator
/opt/etc/init.d/S49wg-obfuscator restart
```

**Ошибка "Address already in use":**
Порт занят

```bash
netstat -ulnp | grep 13255
```

Освободите порт или измените в конфигурации

### 3. WireGuard подключается, но нет интернета

#### Симптомы
- WireGuard показывает "Подключено"
- Ping 10.25.0.1 работает
- Ping внешних адресов не работает или очень медленно

#### Диагностика

**Проверка маршрутов на клиенте:**
В веб-панели Keenetic → "Интернет" → "WireGuard" → проверьте AllowedIPs

**Проверка NAT на сервере:**
```bash
sudo iptables -t nat -L POSTROUTING -n -v
```

Должно быть правило MASQUERADE для 10.25.0.0/16

**Проверка DNS:**
```bash
nslookup google.com
```

#### Решение

**Если нет правил NAT:**
```bash
sudo iptables -t nat -A POSTROUTING -s 10.25.0.0/16 -o eth0 -j MASQUERADE
```

Замените eth0 на ваш внешний интерфейс

**Если проблема с DNS:**
В веб-панели Keenetic установите DNS для WireGuard подключения:
- 8.8.8.8
- 1.1.1.1

**Если AllowedIPs неправильный:**
Переимпортируйте конфигурацию WireGuard с правильным AllowedIPs = 0.0.0.0/0

### 4. Низкая скорость или высокий ping

#### Симптомы
- Скорость значительно ниже канала
- Ping >100ms при близком сервере

#### Диагностика

**Проверка MTU:**
```bash
ping -M do -s 1472 10.25.0.1
```

Если пакеты не проходят, MTU слишком большой

**Проверка нагрузки на роутер:**
```bash
top
```

**Проверка нагрузки на сервер:**
```bash
sudo htop
sudo iotop
```

#### Решение

**Уменьшение MTU:**
В веб-панели Keenetic → "WireGuard" → установите MTU = 1420 или 1400

**Если CPU роутера перегружен:**
- Ограничьте скорость в Keenetic
- Используйте более мощную модель роутера
- Отключите ненужные сервисы на роутере

**Если сервер перегружен:**
- Увеличьте ресурсы VPS
- Уменьшите количество клиентов
- Оптимизируйте iptables правила

### 5. Подключение обрывается периодически

#### Симптомы
- WireGuard отключается каждые несколько минут
- Требуется ручное переподключение

#### Диагностика

**Проверка PersistentKeepalive:**
```bash
cat /opt/etc/Phobos/wg-client.conf | grep PersistentKeepalive
```

**Проверка stability интернет-соединения:**
```bash
ping -c 100 8.8.8.8
```

**Проверка логов obfuscator:**
```bash
logread | grep wg-obfuscator
```

#### Решение

**Добавление PersistentKeepalive:**
Отредактируйте `/opt/etc/Phobos/wg-client.conf`, добавьте в секцию [Peer]:
```ini
PersistentKeepalive = 25
```

Переимпортируйте конфигурацию в Keenetic

**Если obfuscator падает:**
Проверьте память:
```bash
free -m
```

Если мало памяти, отключите ненужные приложения Entware

### 6. После перезагрузки не работает

#### Симптомы
- После перезагрузки роутера WireGuard не подключается
- obfuscator не запущен

#### Диагностика

**Проверка init скрипта:**
```bash
ls -la /opt/etc/init.d/S49wg-obfuscator
```

**Проверка автозапуска WireGuard:**
В веб-панели Keenetic → "WireGuard" → проверьте "Автоматическое подключение"

**Проверка порядка запуска:**
```bash
ls -la /opt/etc/init.d/S*
```

S49 должен запускаться до WireGuard

#### Решение

**Если init скрипт отсутствует или неправильный:**
```bash
cd /tmp/phobos-<client_name>
./install-router.sh
```

**Если автозапуск WireGuard отключен:**
Включите в веб-панели Keenetic

### 7. Высокая нагрузка на CPU

#### Симптомы
- CPU роутера постоянно >80%
- Роутер перегревается
- Интерфейс веб-панели тормозит

#### Диагностика

```bash
top
ps aux | grep wg
```

#### Решение

1. Уменьшите MTU до 1380-1400
2. Ограничьте скорость WireGuard в Keenetic
3. Отключите ненужные Entware приложения:
```bash
opkg list-installed
/opt/etc/init.d/S??<service> stop
```
4. Рассмотрите более мощную модель роутера (ARM вместо MIPS)

### 8. HTTP сервер недоступен

#### Симптомы
- wget/curl не может скачать пакет
- Ошибка "Connection refused"

#### Диагностика

```bash
sudo systemctl status phobos-http
sudo ss -tlnp | grep :8080
curl -I http://localhost:8080/
```

#### Решение

```bash
sudo systemctl restart phobos-http
```

### 9. Токен истек

#### Симптомы
- Ошибка 404 при выполнении команды wget/curl
- Файл <token>.sh не найден

#### Решение

Обратитесь к администратору для генерации нового токена. Токены по умолчанию действуют 1 час (3600 секунд):
```bash
sudo /opt/Phobos/repo/server/scripts/vps-generate-install-command.sh <client_name>
```

Для токена с другим сроком действия (например, 24 часа):
```bash
sudo /opt/Phobos/repo/server/scripts/vps-generate-install-command.sh <client_name> 86400
```

### 10. Ошибки совместимости с BusyBox (Keenetic)

#### Симптомы
- Ошибка "RANDOM: parameter not set" при выполнении init-скрипта
- Ошибка "wget: unrecognized option '--show-progress'"
- Ошибка "bash: not found" на роутере

#### Причина

Роутеры Keenetic используют BusyBox с ограниченной оболочкой `ash` вместо `bash`. Некоторые bash-специфичные конструкции не поддерживаются.

#### Диагностика

**Проверка используемой оболочки:**
```bash
echo $SHELL
ls -l /bin/sh
```

**Проверка версии wget:**
```bash
wget --version
```

BusyBox wget не поддерживает опцию `--show-progress`.

#### Решение

**✅ В версии 0.2.0+ эти проблемы исправлены:**
- Init-скрипт использует `#!/bin/sh` вместо `#!/usr/bin/env bash`
- `$RANDOM` заменен на `$$` (PID процесса)
- Опция `--show-progress` удалена из wget

**Если вы используете старую версию:**

Обратитесь к администратору для пересоздания клиента с актуальными скриптами:
```bash
# На сервере
sudo /opt/Phobos/repo/server/scripts/vps-client-add.sh <client_name>
```

**Временное решение (ручная правка init-скрипта):**
```bash
# На роутере, если скрипт уже загружен
sed -i 's|#!/usr/bin/env bash|#!/bin/sh|' /tmp/init.sh
sed -i 's|\$RANDOM|\$\$|g' /tmp/init.sh
sed -i 's|--show-progress||g' /tmp/init.sh
sh /tmp/init.sh
```

#### Проверка совместимости

Убедитесь, что init-скрипт содержит правильные конструкции:
```bash
# Правильный shebang для BusyBox
head -1 /tmp/init.sh
# Должно быть: #!/bin/sh

# Проверка использования $$
grep "INSTALL_DIR" /tmp/init.sh
# Должно быть: INSTALL_DIR="/tmp/phobos-install-$$"
```

## Сбор диагностической информации

Для создания отчета об ошибке соберите следующую информацию:

### На клиенте

```bash
echo "=== System Info ===" > diagnostic.txt
uname -a >> diagnostic.txt
cat /proc/cpuinfo | head -20 >> diagnostic.txt
free -m >> diagnostic.txt
df -h >> diagnostic.txt

echo "=== Phobos Status ===" >> diagnostic.txt
ps | grep wg-obfuscator >> diagnostic.txt
netstat -ulnp | grep -E "13255|wireguard" >> diagnostic.txt
cat /opt/etc/Phobos/wg-obfuscator.conf >> diagnostic.txt

echo "=== Logs ===" >> diagnostic.txt
cat /opt/etc/Phobos/install.log >> diagnostic.txt
logread | grep -E "wg-obfuscator|wireguard" | tail -50 >> diagnostic.txt

cat diagnostic.txt
```

### На сервере

```bash
sudo bash -c '
echo "=== System Info ===" > diagnostic.txt
uname -a >> diagnostic.txt
free -m >> diagnostic.txt
df -h >> diagnostic.txt

echo "=== Services Status ===" >> diagnostic.txt
systemctl status wg-quick@wg0 >> diagnostic.txt 2>&1
systemctl status wg-obfuscator >> diagnostic.txt 2>&1
systemctl status phobos-http >> diagnostic.txt 2>&1

echo "=== WireGuard Status ===" >> diagnostic.txt
wg show >> diagnostic.txt

echo "=== Network ===" >> diagnostic.txt
ss -ulnp | grep -E "51820|$(grep OBFUSCATOR_PORT /opt/Phobos/server/server.env | cut -d= -f2)" >> diagnostic.txt

echo "=== Recent Logs ===" >> diagnostic.txt
journalctl -u wg-obfuscator -n 50 >> diagnostic.txt
journalctl -u wg-quick@wg0 -n 50 >> diagnostic.txt

cat diagnostic.txt
'
```

## Управление через интерактивное меню

### Запуск интерактивного меню

После установки Phobos доступна команда `phobos` для управления системой:

```bash
sudo phobos
```

### Основные функции меню

- **Управление сервисами**: start/stop/status/logs для WireGuard, obfuscator, HTTP сервера
- **Управление клиентами**: создание, удаление, пересоздание конфигураций
- **Системные функции**: health checks, мониторинг, очистка токенов и симлинков
- **Резервное копирование**: создание бэкапов конфигураций
- **Настройка obfuscator**: изменение параметров сервера

## Получение помощи

При создании запроса на помощь (GitHub Issue, форум и т.д.) приложите:

1. Описание проблемы
2. Что вы уже пробовали
3. Диагностическую информацию (см. выше)
4. Модель роутера (для клиента)
5. Версия прошивки Keenetic (для клиента)
6. ОС и версия (для сервера)

## Типичные проблемы с интерактивным меню

### Команда `phobos` не найдена

**Симптомы:**
- Ошибка "command not found: phobos"

**Диагностика:**
```bash
which phobos
ls -la /usr/local/bin/phobos
```

**Решение:**
Команда `phobos` устанавливается как часть vps-init-all.sh. Если команда не найдена:

1. Проверьте, была ли выполнена установка меню:
```bash
ls -la /opt/Phobos/repo/server/scripts/vps-install-menu.sh
```

2. Вручную установите меню:
```bash
sudo /opt/Phobos/repo/server/scripts/vps-install-menu.sh
```

### Интерактивное меню не запускается

**Симптомы:**
- Ошибка при запуске `sudo phobos`
- Нет доступа к меню

**Решение:**
1. Проверьте права доступа:
```bash
ls -la /usr/local/bin/phobos
```

2. Перезапустите установку меню:
```bash
sudo /opt/Phobos/repo/server/scripts/vps-install-menu.sh
```

### Проблемы с подтверждением изменений в настройках obfuscator

**Симптомы:**
- Неожиданные запросы подтверждения или ошибки при изменении настроек

**Описание:**
В предыдущих версиях могло быть двойное подтверждение при изменении критических параметров (порт/ключ). В актуальных версиях:
- Для критических изменений (порт или ключ) требуется только одно подтверждение "YES"
- Тестирование конфигурации больше не выполняется перед применением изменений
- После подтверждения изменения применяются сразу с созданием резервной копии

**Решение:**
Обновите скрипты до последней версии, чтобы воспользоваться упрощенным процессом изменения настроек.

## Профилактика проблем

### Регулярные проверки

**Еженедельно:**
```bash
sudo /opt/Phobos/repo/server/scripts/vps-health-check.sh
sudo /opt/Phobos/repo/server/scripts/vps-monitor-clients.sh
```

**Ежемесячно:**
- Обновление системных пакетов
- Проверка свободного места
- Ротация логов
- Резервное копирование конфигурации

### Мониторинг

Настройте мониторинг доступности:
- Uptime monitoring (UptimeRobot, Better Uptime)
- Ping мониторинг сервера
- Алерты при недоступности

### Резервное копирование

**Сервер - еженедельно:**
```bash
sudo tar czf /root/phobos-backup-$(date +%Y%m%d).tar.gz \
  /opt/Phobos/clients \
  /opt/Phobos/server \
  /opt/Phobos/tokens \
  /etc/wireguard/wg0.conf
```

**Клиент - при изменении конфигурации:**
```bash
tar czf /tmp/phobos-backup.tar.gz /opt/etc/Phobos /opt/etc/init.d/S49wg-obfuscator
```

## Контакты

- GitHub Issues: https://github.com/Ground-Zerro/Phobos/issues
- wg-obfuscator: https://github.com/ClusterM/wg-obfuscator/issues
