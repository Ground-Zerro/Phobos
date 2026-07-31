# Phobos for Windows

Клиент Phobos для Windows: WireGuard-туннель с обфускацией (`wg-obfuscator`), где трафик
маскируется под STUN/RTP или идёт через обфусцированный SOCKS5. Ядро WireGuard —
kernel-драйвер [WireGuardNT](https://git.zx2c4.com/wireguard-nt/about/), SOCKS5-режим работает
через Wintun и собственный сетевой стек.

Форк [WireGuard for Windows](https://git.zx2c4.com/wireguard-windows/about/).

## Сборка

```bash
./build-windows.sh              # exe + wg.exe + MSI для amd64, x86, arm64
./build-windows.sh --no-installer   # только исполняемые файлы, wine не нужен
./build-windows.sh --clean          # удалить результаты сборки
```

Скрипт сам проверяет и доустанавливает тулчейны (llvm-mingw, Go, WiX, wine). Результат:
`<арх>/phobos.exe`, `<арх>/wg.exe`, `installer/dist/phobos-<арх>-<версия>.msi`.

Иконки лежат в `ui/icon/` уже собранными; пересобрать из исходников —
`./ui/icon/build-icons.sh` (нужны `rsvg-convert` и ImageMagick).

## Тесты

```bash
go test ./phobos/... ./conf/ ./ui/syntax/          # обычный прогон
go test -tags phoboscref ./phobos/...              # плюс побайтовая сверка с C-обфускатором
```

Сверка требует канонические исходники в `../src/phobos-obfuscator/`.

## Документация

- [`adminregistry.md`](docs/adminregistry.md) — ключи реестра для администратора.
- [`attacksurface.md`](docs/attacksurface.md) — разбор компонентов с точки зрения безопасности.
- [`buildrun.md`](docs/buildrun.md) — сборка, локализация и разработка.
- [`enterprise.md`](docs/enterprise.md) — использование в корпоративной среде.
- [`netquirk.md`](docs/netquirk.md) — особенности маршрутизации и kill-switch.

## Лицензия

Репозиторий распространяется по лицензии MIT. Полный текст — в [`COPYING`](COPYING);
он же устанавливается вместе с программой как `COPYING.txt`.

Код унаследован от WireGuard for Windows, авторские права на него принадлежат WireGuard LLC;
условие MIT о сохранении уведомления об авторстве выполняется файлом `COPYING`.
