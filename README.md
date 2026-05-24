# wg-easy + Phobos obfuscator

[![Build & Publish Image](https://github.com/Ground-Zerro/Phobos/actions/workflows/publish-image.yml/badge.svg?branch=ph-wg-easy)](https://github.com/Ground-Zerro/Phobos/actions/workflows/publish-image.yml)
[![GitHub Stars](https://img.shields.io/github/stars/Ground-Zerro/Phobos)](https://github.com/Ground-Zerro/Phobos/stargazers)
[![License](https://img.shields.io/github/license/Ground-Zerro/Phobos)](LICENSE)

WireGuard admin panel with a built-in STUN obfuscator. Traffic from the client to the server is masked as STUN and XOR-encoded — to bypass DPI in regions with blocks.

<p align="center">
  <img src="./assets/screenshot.png" width="802" alt="wg-easy Screenshot" />
</p>

## Features

- WireGuard + Web UI + XOR/STUN obfuscator in a single container.
- s6-overlay supervises `node` and `wg-obfuscator` as independent long-running services.
- Public WireGuard port is not exposed; only the obfuscator UDP port is published.
- Per-client **install-link**: one shell command installs a full Phobos package on the client (WG config + platform installer + multi-arch obfuscator binary).
- Admin UI for tuning obfuscator level, masking mode, key, port.
- SQLite + Drizzle, multilanguage UI, 2FA, per-client firewall, IPv6, CIDR support.

## Quickstart (generic Docker)

```yaml
services:
  wg-easy:
    image: ghcr.io/ground-zerro/phobos:latest
    environment:
      - OBF_PORT=51822
    ports:
      - "51822:51822/udp"
      - "51821:51821/tcp"
    volumes:
      - etc_wireguard:/etc/wireguard
      - sqlite_data:/app/server/data
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped

volumes:
  etc_wireguard:
  sqlite_data:
```

Open `http://<host>:51821`, complete the initial setup, create a client.

## One-command server deploy

Run one command on a fresh server:

```shell
curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/ph-wg-easy/deploy.sh | sudo bash
```

Script behavior:

- installs Docker + Compose plugin (if missing),
- downloads deployment files from this repository,
- pulls ready project image from `ghcr.io/ground-zerro/phobos`,
- starts the stack without server-side image build,
- opens the setup wizard: create admin account, set hostname, configure TLS.

After deployment open `http://<WG_HOST>:51821/` — the wizard guides through:
1. Admin account (username + password)
2. Server host (IP address or domain)
3. TLS certificate (self-signed / Let's Encrypt / skip)

> Make sure port **80** is open for Let's Encrypt HTTP challenge.

Optional parameters:

```shell
WG_HOST=<PUBLIC_IP_OR_DOMAIN> \
OBF_PORT=51822 \
WG_EASY_IMAGE=ghcr.io/ground-zerro/phobos:latest \
curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/ph-wg-easy/deploy.sh | sudo bash
```

To skip the wizard and pre-configure admin credentials via environment:

```shell
INIT_ENABLED=true \
INIT_USERNAME=admin \
INIT_PASSWORD=YourPassword \
WG_HOST=<PUBLIC_IP_OR_DOMAIN> \
curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/Phobos/ph-wg-easy/deploy.sh | sudo bash
```

Ports:

- Web UI: `http://<WG_HOST>:51821/`
- Obfuscator: `UDP <WG_HOST>:<OBF_PORT>`

## How it works

```
Client device                    Server (Docker)
─────────────                    ────────────────
 app ─► 127.0.0.1:13255           0.0.0.0:<OBF_PORT>
        (local WG client)          (wg-obfuscator server)
           │                            │  STUN unwrap + XOR decode
           │ plain WG                   ▼
           ▼                       127.0.0.1:51820 (wg0, loopback-only)
 127.0.0.1:13255                        │
 (wg-obfuscator client)                 │  WG
           │                            ▼
           │ XOR + STUN wrap       FORWARD → internet
           ▼
 UDP → <server_ip>:<OBF_PORT>
```

## Client installation

1. Admin creates a client in the Web UI.
2. Admin clicks the **install-link** button — the command is copied to the clipboard:
   ```
   curl -sL http://<origin>/api/install/<token> | sh
   ```
3. Admin pastes the command on the target device. The script downloads the Phobos package, detects the platform, installs `wg-obfuscator` and configures WireGuard.

## Supported client platforms

- Keenetic / Netcraze (Entware + RCI API)
- OpenWrt / ImmortalWrt (opkg + UCI)
- Debian / Ubuntu Linux (apt + systemd)
- 3x-ui panels (SQLite integration)

## Obfuscator tuning

| Level | Key length | Max dummy |
|-------|-----------|-----------|
| 1 — Light | 3 | 4 |
| 2 — Sufficient | 6 | 10 |
| 3 — Average | 20 | 20 |
| 4 — Above average | 50 | 50 |
| 5 — Nightmare | 255 | 100 |

## Remote deploy scripts

Additional helpers in `scripts/deploy/` are available for SSH-based remote operations and updates.

## Development

```shell
pnpm dev
```

## License

AGPL-3.0-only — see [LICENSE](LICENSE).

This project is not affiliated, associated, authorized, endorsed by, or in any way officially connected with Jason A. Donenfeld, ZX2C4 or Edge Security. "WireGuard" and the "WireGuard" logo are registered trademarks of Jason A. Donenfeld.
