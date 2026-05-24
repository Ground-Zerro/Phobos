# Формат ссылки `phobos://`

Эта ссылка — компактный, копируемый-в-буфер транспорт полной клиентской конфигурации (WireGuard + obfuscator). Назначение: альтернатива QR-коду и `.conf`-файлу для импорта на устройство клиентским приложением (роутер-помощник, мобильное приложение, расширение).

> **Это не secret link.** Ссылка содержит приватный ключ клиента и общий ключ обфускатора; по сути это сам `.conf`. Передавайте по защищённому каналу.

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

Это **обычный текст `.conf`-файла** клиента в кодировке UTF-8, со стандартными INI-секциями WireGuard и нашим расширением `[instance]` для obfuscator-клиента.

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

Между секциями ровно одна пустая строка, как в `.conf` который PhobosWG отдаёт через `/api/client/<id>/config`. Никаких преобразований не делать — payload это байт-в-байт тот же файл.

### 2.3 Обязательные поля и значение `none`

Все поля секций — обязательные. Если значение отсутствует (например, у клиента не задан собственный DNS), производитель ссылки **перед base64-кодированием** дописывает в payload строку с литералом `none` для каждого недостающего обязательного поля:

```ini
[Interface]
PrivateKey = MBrnZoTdyT/LR4XpB7tElSxyVTQdXFw0tvVJOMSL/GI=
Address = 10.8.0.4/32, fdcc:ad94:bacf:61a4::cafe:4/128
MTU = none
DNS = none
…
```

Клиентское приложение при импорте трактует `= none` как «значение не задано, использовать собственный default». Это поведение обязательно — без него парсер на клиенте может вылететь на «незнакомом» формате или потерять поле молча.

**Важно**: padding применяется **только** к payload phobos://-ссылки, не к оригинальному `.conf`, который доставляется через `/api/client/<id>/config`, копируется кликом по QR или встраивается в QR-картинку. Стандартный `.conf` остаётся валидным для wg-quick, WireGuard for Android/iOS и любого классического WG-парсера — те не поймут `DNS = none` и могут сломаться. Padding выполняется в `src/app/utils/phobosLink.ts:padConfWithNone` непосредственно перед base64-кодированием.

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

Конфиг из §2.2 → закодированный (укорочено):

```
phobos://W0ludGVyZmFjZV0KUHJpdmF0ZUtleSA9IE1Ccm5ab1RkeVQvTFI0WHBCN3RFbFN4eVZUUWRYRncwdHZWSk9NU0wvR0k9CkFkZHJlc3MgPSAxMC44LjAuNC8zMiwgZmRjYzphZDk0OmJhY2Y6NjFhNDo6Y2FmZTo0LzEyOApNVFUgPSAxNDIwCkROUyA9IDguOC44LjgsIDIwMDE6NDg2MDo0ODYwOjo4ODg4CgpbUGVlcl0KUHVibGljS2V5ID0gZy9HNHkyWGtUWTVtUExNWVlYWENhcnZ5eFVTSFV6TTF2cElZUkh3d0ZUND0KUHJlc2hhcmVkS2V5ID0gbDVURldNM3RJUjBEazg3dVBFblZrcXFsNExta2NQb2VXbU9LWktmeWVmWT0KQWxsb3dlZElQcyA9IDAuMC4wLjAvMCwgOjovMApQZXJzaXN0ZW50S2VlcGFsaXZlID0gMApFbmRwb2ludCA9IDEyNy4wLjAuMToxMzI1NQoKW2luc3RhbmNlXQpzb3VyY2UtaWYgPSAxMjcuMC4wLjEKc291cmNlLWxwb3J0ID0gMTMyNTUKdGFyZ2V0ID0gMTMwLjQ5LjE4NS4xMzY6NTE4MjQKa2V5ID0gWFIwTkVmOE1oR0FHY0NwYwptYXNraW5nID0gU1RVTgp2ZXJib3NlID0gSU5GTwppZGxlLXRpbWVvdXQgPSAzMDAKbWF4LWR1bW15ID0gNDU#Mobil-phone
```

Декодирование:

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

---

## 6. Подводные камни

### 6.1 Парсинг URL в JS

`new URL("phobos://...")` ведёт себя по-разному в зависимости от наличия `:port`:
- `url.host` = `hostname:port` (если порт есть)
- `url.hostname` = только host часть

Для нашего payload (без `:` — base64url его не содержит) `url.host === url.hostname`. Безопасно использовать `url.hostname`.

### 6.2 Length

Типичный `.conf` ≈ 600–900 байт. base64url увеличивает до ≈ 800–1200 символов. Плюс схема и fragment → итоговая ссылка ~900–1300 символов. В пределах comfortable для копирования и QR-кода (URL ниже 2k проходит через QR ECC-M без проблем).

### 6.3 Поле `verbose` и фиксированные значения

`verbose = INFO` и некоторые поля `[instance]` сейчас захардкожены. Они тоже включаются в payload as-is — клиент-приложение должно их корректно парсить и/или игнорировать неизвестные.

### 6.4 Locale-зависимые символы

`encodeURIComponent` корректно работает с любым UTF-8, включая кириллицу/китайский в client name. Кодирование `.conf` через base64 тоже сохраняет UTF-8 целиком (escape/unescape-трюк выше — для совместимости с `btoa` который ожидает binary-safe строку).

---

## 7. Эталонные реализации

Серверная (Node/TypeScript) — см. `src/server/utils/PhobosLink.ts` (создаётся в рамках плана интеграции в `docs/plans/`).

Клиентская (минимальная, для проверки):

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
  return { conf, name };
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
