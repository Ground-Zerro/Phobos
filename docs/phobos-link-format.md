# Формат ссылки `phobos://`

Эта ссылка — компактный, копируемый-в-буфер транспорт полной клиентской конфигурации. Один и тот же формат покрывает оба протокола клиента:

- **WireGuard** — секции `[Interface]` + `[Peer]` + `[instance]` (obfuscator).
- **SOCKS5** — только `[instance]` (obfuscator, `mode = socks5`) + `[socks5]` (логин/пароль прокси). WireGuard-секций нет вовсе.

Назначение: альтернатива QR-коду и `.conf`-файлу для импорта на устройство клиентским приложением (роутер-помощник, мобильное приложение, расширение).

> **Это не secret link.** Ссылка содержит приватный ключ клиента (WireGuard) или логин/пароль SOCKS5 и общий ключ обфускатора; по сути это сам `.conf`. Передавайте по защищённому каналу.

> **Формат ссылки от добавления SOCKS5 не изменился.** Payload — это base64url произвольного текста `.conf`, поэтому новый ключ `mode`, роль `role` и секция `[socks5]` едут внутри полезной нагрузки без единого изменения структуры `phobos://<payload>#<name>`. Производитель и потребитель ссылки различают протоколы по содержимому конфига (наличие `mode = socks5`), а не по форме URI. См. §5.6.

---

## 1. Общий вид

```
phobos://<base64url(conf_text)>#<urlencoded(client_name)>
```

| Компонент | Описание | Обязательно |
|-----------|----------|------|
| схема `phobos://` | URI scheme; маркер для регистрации обработчика на клиентской ОС | да |
| `<payload>` (host часть) | весь клиентский `.conf` в UTF-8, закодированный в **base64url** (RFC 4648 §5) без padding | да |
| `#<fragment>` | имя клиента, URL-encoded; если имени нет — литерал `none` | да |

---

## 2. Кодирование payload

### 2.1 Алфавит

Стандартный base64 (`A–Z a–z 0–9 + / =`) **не подходит** для URI:
- `/` интерпретируется парсером как разделитель пути;
- `+` — как пробел в query-string;
- `=` — padding, видимый, бесполезный в base64url.

Используем **base64url** (RFC 4648 §5):
- `+` → `-`
- `/` → `_`
- padding `=` опускается.

JS/Python референсные реализации:

```js
// encode
const b64url = btoa(unescape(encodeURIComponent(confText)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

// decode
const padded = b64url.replace(/-/g, '+').replace(/_/g, '/')
  + '=='.slice((b64url.length + 3) % 4);
const conf = decodeURIComponent(escape(atob(padded)));
```

```python
import base64
# encode
b64url = base64.urlsafe_b64encode(conf_text.encode("utf-8")).decode("ascii").rstrip("=")
# decode
pad = "=" * (-len(b64url) % 4)
conf = base64.urlsafe_b64decode(b64url + pad).decode("utf-8")
```

### 2.2 Содержимое (`conf_text`)

Это **обычный текст `.conf`-файла** клиента в кодировке UTF-8, со стандартными INI-секциями WireGuard и нашими расширениями `[instance]` (obfuscator-клиент) и `[socks5]` (креды прокси). Набор секций зависит от протокола клиента, который задаётся ключом `mode` в секции `[instance]`.

#### 2.2.1 Ключ `mode`

Ключ `mode` в секции `[instance]` — единственный маркер протокола:

| Значение | Смысл | Секции конфига |
|----------|-------|----------------|
| `wireguard` (или ключ отсутствует) | WireGuard-туннель, obfuscator в UDP-режиме | `[Interface]`, `[Peer]`, `[instance]` |
| `socks5` | локальный SOCKS5-прокси, obfuscator в TCP-режиме | `[instance]`, `[socks5]` |

`mode` и `role` — валидные ключи бинарника `wg-obfuscator` (`-M`/`--mode`, `-R`/`--role`), поэтому попадают в `[instance]` как есть. Для WireGuard `mode` можно опускать (обратная совместимость со старыми ссылками: отсутствие `mode` = `wireguard`).

#### 2.2.2 WireGuard (`mode = wireguard`)

Все три секции **обязательны**:

```ini
[Interface]
PrivateKey = MBrnZoTdyT/LR4XpB7tElSxyVTQdXFw0tvVJOMSL/GI=
Address = 10.8.0.4/32, fdcc:ad94:bacf:61a4::cafe:4/128
MTU = 1420
DNS = 8.8.8.8, 2001:4860:4860::8888

[Peer]
PublicKey = g/G4y2XkTY5mPLMYYXXCarvyxUSHUzM1vpIYRHwwFT4=
PresharedKey = l5TFWM3tIR0Dk87uPEnVkqql4LmkcPoeWmOKZKfyefY=
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 0
Endpoint = 127.0.0.1:13255

[instance]
source-if = 127.0.0.1
source-lport = 13255
target = 130.49.185.136:51824
key = XR0NEf8MhGAGcCpc
masking = STUN
verbose = INFO
idle-timeout = 300
max-dummy = 45
```

#### 2.2.3 SOCKS5 (`mode = socks5`)

WireGuard-секций нет. `[instance]` описывает клиентскую сторону обфускатора (`role = client`, TCP-туннель на сервер), `[socks5]` несёт креды для локального прокси-указателя приложения (`socks5://<login>:<password>@127.0.0.1:<source-lport>`):

```ini
[instance]
mode = socks5
role = client
source-if = 127.0.0.1
source-lport = 1080
target = vpn.example.com:51824
key = XR0NEf8MhGAGcCpc
masking = MEDIA
verbose = error
media-ssrc = 305419896

[socks5]
login = Ab3Kq
password = Zx9Lm
```

- `source-lport` — локальный порт, на котором обфускатор поднимает SOCKS5-listener; приложение указывает браузер/систему на `127.0.0.1:<source-lport>`.
- `target` — публичный адрес сервера (`serverPublicDomain` или `serverPublicIpV4`) и внешний порт пресета.
- WG-специфичные поля (`obfuscate-bytes`, `max-dummy`, `idle-timeout`) в SOCKS5-конфиге не участвуют.

> **Секцию `[socks5]` нельзя скармливать бинарнику `wg-obfuscator`.** Его парсер конфига завершает работу с ошибкой на неизвестном ключе, а `login`/`password` — это не опции обфускатора (SOCKS5 role=client прозрачно ретранслирует RFC1929-хендшейк приложения). Импортирующее приложение читает `[socks5]` для настройки локального прокси-указателя, а бинарнику передаёт **только** секцию `[instance]`. Именно поэтому креды вынесены в отдельную секцию, а не добавлены полями в `[instance]`.

Между секциями ровно одна пустая строка, как в `.conf` который PhobosWG отдаёт через `/api/client/<id>/config`. Никаких преобразований не делать — payload это байт-в-байт тот же файл. Для SOCKS5-клиента `/api/client/<id>/config` возвращает `[instance]` + `[socks5]` (та же строка идёт и в QR-код); бинарный конфиг из установочного пакета (`wg-socks5-obfuscator.conf`) содержит только `[instance]` и генерируется отдельно.

#### Поле `masking`

Допустимые значения — `STUN`, `MEDIA`, `AUTO`, `NONE` (плюс `TLS` только для SOCKS5). Значение берётся из пресета обфускатора (`buildClientObfConf` для WireGuard, `buildSocks5ClientObfConf` для SOCKS5) и попадает в payload как есть; и `.conf`, и QR-код, и phobos://-ссылка строятся из одного и того же `getClientFullConfig`, поэтому режим маскировки переносится всеми тремя транспортами автоматически.

Режим **`MEDIA`** добавляет в payload поле `media-ssrc` **только** если в пресете задан статический SSRC (иначе оно опускается и обе стороны берут случайный SSRC per-connection). Прочие RTP-параметры (`media-pt`, `media-clock`) остаются случайными (`0`) — они не требуют согласования сторон, а `obfuscate-bytes` обе стороны берут из дефолта одного и того же бинарника (`16` для MEDIA). Для WireGuard-`MEDIA` статический SSRC панель не выставляет; для SOCKS5-`MEDIA` он переносится, если задан в пресете (`ObfuscatorPreset.mediaSsrc`), — это единственное mode-специфичное поле маскировки в payload.

### 2.3 Обязательные поля и значение `none`

Набор обязательных полей выбирается по протоколу (по наличию `mode = socks5`):

| Секция | WireGuard | SOCKS5 |
|--------|-----------|--------|
| `[Interface]` | `PrivateKey`, `Address`, `MTU`, `DNS` | — (секции нет) |
| `[Peer]` | `PublicKey`, `PresharedKey`, `AllowedIPs`, `PersistentKeepalive`, `Endpoint` | — (секции нет) |
| `[instance]` | `source-if`, `source-lport`, `target`, `key`, `masking`, `verbose`, `idle-timeout`, `max-dummy` | `mode`, `role`, `source-if`, `source-lport`, `target`, `key`, `masking`, `verbose` |
| `[socks5]` | — | `login`, `password` |

Паддинг применяется только к секциям, реально присутствующим в конфиге, — поэтому WireGuard-поля никогда не «протекают» в SOCKS5-конфиг и наоборот. Если значение обязательного поля отсутствует (например, у WireGuard-клиента не задан собственный DNS), производитель ссылки **перед base64-кодированием** дописывает в payload строку с литералом `none` для каждого недостающего обязательного поля:

```ini
[Interface]
PrivateKey = MBrnZoTdyT/LR4XpB7tElSxyVTQdXFw0tvVJOMSL/GI=
Address = 10.8.0.4/32, fdcc:ad94:bacf:61a4::cafe:4/128
MTU = none
DNS = none
…
```

Клиентское приложение при импорте трактует `= none` как «значение не задано, использовать собственный default». Это поведение обязательно — без него парсер на клиенте может вылететь на «незнакомом» формате или потерять поле молча.

**Важно**: padding применяется **только** к payload phobos://-ссылки, не к оригинальному `.conf`, который доставляется через `/api/client/<id>/config`, копируется кликом по QR или встраивается в QR-картинку. Стандартный `.conf` остаётся валидным для wg-quick, WireGuard for Android/iOS и любого классического WG-парсера — те не поймут `DNS = none` и могут сломаться. Padding выполняется в `src/app/utils/phobosLink.ts:padConfWithNone` непосредственно перед base64-кодированием; функция сама выбирает WireGuard- или SOCKS5-набор обязательных полей по наличию `mode = socks5`.

---

## 3. Fragment (имя клиента)

После `#` идёт URL-encoded имя клиента. Берётся из `client.name` без дополнительной обработки кроме `encodeURIComponent`.

Если имя пустое (`""` или `null`) — записывается литерал `none`:

```
phobos://<payload>#none
```

Fragment **не входит** в payload и не валидируется криптографически. Используется только клиентским приложением для подсказки имени соединения (например, заголовок в списке профилей).

---

## 4. Полный пример

WireGuard-конфиг из §2.2.2 → закодированный (укорочено):

```
phobos://W0ludGVyZmFjZV0KUHJpdmF0ZUtleSA9IE1Ccm5ab1RkeVQvTFI0WHBCN3RFbFN4eVZUUWRYRncwdHZWSk9NU0wvR0k9CkFkZHJlc3MgPSAxMC44LjAuNC8zMiwgZmRjYzphZDk0OmJhY2Y6NjFhNDo6Y2FmZTo0LzEyOApNVFUgPSAxNDIwCkROUyA9IDguOC44LjgsIDIwMDE6NDg2MDo0ODYwOjo4ODg4CgpbUGVlcl0KUHVibGljS2V5ID0gZy9HNHkyWGtUWTVtUExNWVlYWENhcnZ5eFVTSFV6TTF2cElZUkh3d0ZUND0KUHJlc2hhcmVkS2V5ID0gbDVURldNM3RJUjBEazg3dVBFblZrcXFsNExta2NQb2VXbU9LWktmeWVmWT0KQWxsb3dlZElQcyA9IDAuMC4wLjAvMCwgOjovMApQZXJzaXN0ZW50S2VlcGFsaXZlID0gMApFbmRwb2ludCA9IDEyNy4wLjAuMToxMzI1NQoKW2luc3RhbmNlXQpzb3VyY2UtaWYgPSAxMjcuMC4wLjEKc291cmNlLWxwb3J0ID0gMTMyNTUKdGFyZ2V0ID0gMTMwLjQ5LjE4NS4xMzY6NTE4MjQKa2V5ID0gWFIwTkVmOE1oR0FHY0NwYwptYXNraW5nID0gU1RVTgp2ZXJib3NlID0gSU5GTwppZGxlLXRpbWVvdXQgPSAzMDAKbWF4LWR1bW15ID0gNDU#Mobil-phone
```

SOCKS5-конфиг из §2.2.3 → закодированный (укорочено). Обёртка та же — меняется только декодированное содержимое:

```
phobos://W2luc3RhbmNlXQptb2RlID0gc29ja3M1CnJvbGUgPSBjbGllbnQKc291cmNlLWlmID0gMTI3LjAuMC4xCnNvdXJjZS1scG9ydCA9IDEwODAKdGFyZ2V0ID0gdnBuLmV4YW1wbGUuY29tOjUxODI0CmtleSA9IFhSME5FZjhNaEdBR2NDcGMKbWFza2luZyA9IE1FRElBCnZlcmJvc2UgPSBlcnJvcgptZWRpYS1zc3JjID0gMzA1NDE5ODk2Cgpbc29ja3M1XQpsb2dpbiA9IEFiM0txCnBhc3N3b3JkID0gWng5TG0#Mobil-phone
```

Декодирование (одинаково для обоих протоколов):

```js
const link = "phobos://...#Mobil-phone";
const url = new URL(link);
const b64url = url.hostname; // или url.host если порта нет
// (см. ниже про подводный камень)
const padded = b64url.replace(/-/g, '+').replace(/_/g, '/')
  + '=='.slice((b64url.length + 3) % 4);
const confText = decodeURIComponent(escape(atob(padded)));
const name = decodeURIComponent(url.hash.slice(1));
```

---

## 5. Дизайн-решения и обоснования

### 5.1 Почему base64 а не структурированный формат с разделителями

В клиентских полях WireGuard встречаются буквально все типичные URI-разделители:

| Символ | Где встречается |
|--------|-----------------|
| `=` | конец base64 ключей (PrivateKey, PublicKey, PresharedKey) |
| `:` | IPv6 (`fdcc:ad94:bacf:61a4::cafe:4`), Endpoint, target |
| `,` | Address (несколько адресов), AllowedIPs, DNS (несколько серверов) |
| `/` | CIDR-маска (`/32`, `/128`, `/0`) |
| `&` | теоретически может появиться в hook-командах (`iptables ... &`) |

Любая структурированная схема `key=value&key=value` или `[Section]&Key=Value` уязвима к коллизиям — потребуется тщательное экранирование/URL-encode каждого поля. Base64 убивает проблему полностью одним приёмом.

### 5.2 Почему не raw text в URI

`phobos://<raw conf text>` сломается на первом же `:` или `/` — стандартный URL-парсер интерпретирует их как часть структуры URI. К тому же символы новой строки в URI не допускаются.

### 5.3 Почему base64url а не стандартный base64

Стандартный base64 включает `/`, `+`, `=` — все три плохо живут в URI. URL-encode каждого символа `%2F`, `%2B`, `%3D` раздувает строку и снова создаёт читаемые `=`-знаки которые могут спутать парсеры. base64url решает это на уровне алфавита.

### 5.4 Зачем fragment (а не часть payload)

`#fragment` — стандартная часть URI, не отправляется в HTTP-запросах и не индексируется. Хороший контейнер для имени клиента: видно человеку при копировании ссылки, не мешает payload-парсингу, и легко достаётся через `URL().hash`.

### 5.5 Что НЕ делается этой ссылкой

- **Не шифрует payload.** base64 — это кодирование, не шифрование. Любой кто видит ссылку — видит и PrivateKey клиента. Передавайте по защищённому каналу (мессенджер с E2EE, физическая близость).
- **Не подписывает payload.** Подмена ссылки в недоверенном канале возможна. Если важна аутентификация — оборачивайте ссылку в подписанный JWT или используйте install-link (`/api/install/<token>`), который короткоживущий и требует HTTPS.
- **Не содержит версию схемы.** Все ссылки сейчас формата v1. Если в будущем потребуется breaking change — будет введён префикс `phobos://v2.<payload>...`; парсер должен по отсутствию префикса считать v1.

### 5.6 Почему добавление SOCKS5 не меняет формат ссылки

Это прямое следствие §5.1: payload — непрозрачный base64url всего текста `.conf`, а не структурированный набор полей. Формат ссылки ничего не знает о WireGuard или SOCKS5 — он переносит байты конфига. Поэтому новый ключ `mode`, роль `role` и секция `[socks5]` — это изменения **содержимого** payload, а не его **обёртки**. Схема `phobos://`, алгоритм base64url, семантика `#fragment` (имя клиента) и клиентский декодер (§7) остаются идентичными для обоих протоколов; декодер отдаёт `.conf`, а разбор `mode`/секций — уже забота импортирующего приложения.

Практические следствия:

- Старые ссылки (WireGuard, без `mode`) продолжают работать без изменений — отсутствие `mode` трактуется как `wireguard`.
- Один и тот же генератор (`buildPhobosLink`) и один и тот же декодер обслуживают оба протокола; ветвление только в выборе набора обязательных полей (`padConfWithNone`).
- Регистрация обработчика `phobos://` на клиентской ОС не требует изменений — тип ссылки распознаётся после декодирования.

### 5.7 Почему креды SOCKS5 — отдельная секция `[socks5]`, а не поля `[instance]`

Секция `[instance]` целиком пригодна для скармливания бинарнику `wg-obfuscator` (все её ключи — валидные опции). Парсер конфига бинарника завершается с ошибкой на любом неизвестном ключе, а `login`/`password` опциями обфускатора не являются: SOCKS5 role=client прозрачно ретранслирует RFC1929-хендшейк приложения, ему креды не нужны. Держать их полем `[instance]` — значит либо сломать бинарник, либо заставить импортёр вырезать «магические» ключи. Отдельная секция `[socks5]` даёт чистую границу: `[instance]` → бинарнику, `[socks5]` → в настройку локального прокси-указателя приложения.

---

## 6. Подводные камни

### 6.1 Парсинг URL в JS

`new URL("phobos://...")` ведёт себя по-разному в зависимости от наличия `:port`:
- `url.host` = `hostname:port` (если порт есть)
- `url.hostname` = только host часть

Для нашего payload (без `:` — base64url его не содержит) `url.host === url.hostname`. Безопасно использовать `url.hostname`.

### 6.2 Length

Типичный WireGuard-`.conf` ≈ 600–900 байт. base64url увеличивает до ≈ 800–1200 символов. Плюс схема и fragment → итоговая ссылка ~900–1300 символов. SOCKS5-конфиг заметно короче (нет WG-секций с ключами) — ≈ 250–350 байт, ссылка ~350–500 символов. Оба варианта в пределах comfortable для копирования и QR-кода (URL ниже 2k проходит через QR ECC-M без проблем).

### 6.3 Поле `verbose`, фиксированные значения и неизвестные ключи

`verbose` и некоторые поля `[instance]` (`source-if = 127.0.0.1`, `role = client` для SOCKS5) сейчас захардкожены. Они включаются в payload as-is. Общее правило для импортёра: **разбирать по секциям, `[instance]` отдавать бинарнику `wg-obfuscator`, а `[socks5]` — в настройку локального прокси; неизвестные ключи в `[instance]` игнорировать, но никогда не подмешивать в `[instance]` ключи из `[socks5]`** (бинарник упадёт на них, §5.7).

### 6.4 Locale-зависимые символы

`encodeURIComponent` корректно работает с любым UTF-8, включая кириллицу/китайский в client name. Кодирование `.conf` через base64 тоже сохраняет UTF-8 целиком (escape/unescape-трюк выше — для совместимости с `btoa` который ожидает binary-safe строку).

---

## 7. Эталонные реализации

Производитель (Nuxt-панель, TypeScript) — `src/app/utils/phobosLink.ts` (`buildPhobosLink` + `padConfWithNone`). Обфускатор-секции конфига собираются на сервере в `src/server/utils/Obfuscator.ts` (`buildClientObfConf`, `buildSocks5ClientObfConf`, `buildSocks5CredentialsSection`) и склеиваются в `WireGuard.getClientFullConfig`.

Клиентская (минимальная, для проверки) — декодер одинаков для обоих протоколов, различие только в разборе результата:

```js
function decodePhobosLink(link) {
  const url = new URL(link);
  if (url.protocol !== "phobos:") throw new Error("not a phobos link");
  const b64url = url.hostname;
  const pad = "=".repeat((4 - (b64url.length % 4)) % 4);
  const conf = decodeURIComponent(
    escape(atob(b64url.replace(/-/g, "+").replace(/_/g, "/") + pad))
  );
  const name = decodeURIComponent(url.hash.slice(1)) || "none";
  // Протокол определяется по содержимому, а не по форме ссылки:
  const mode = /^\s*mode\s*=\s*socks5\s*$/im.test(conf) ? "socks5" : "wireguard";
  return { conf, name, mode };
}
```

```python
from urllib.parse import urlparse, unquote
import base64

def decode_phobos_link(link: str):
    u = urlparse(link)
    if u.scheme != "phobos":
        raise ValueError("not a phobos link")
    b64url = u.hostname or u.netloc.split(":")[0]
    pad = "=" * (-len(b64url) % 4)
    conf = base64.urlsafe_b64decode(b64url + pad).decode("utf-8")
    name = unquote(u.fragment) or "none"
    return conf, name
```
