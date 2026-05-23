FROM docker.io/library/node:lts-alpine AS build
WORKDIR /app

RUN apk add --no-cache python3
RUN npm install --global corepack@latest
RUN corepack enable pnpm

COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY src ./
RUN pnpm build

RUN node -e " \
const path = require('path'); \
const {cpSync, mkdirSync, existsSync} = require('fs'); \
const arch = process.arch === 'x64' ? 'x64' : process.arch === 'arm64' ? 'arm64' : null; \
if (!arch) { console.error('Unsupported arch:', process.arch); process.exit(1); } \
const pkg = '@libsql/linux-' + arch + '-musl'; \
const out = '/tmp/libsql-native/linux-' + arch + '-musl'; \
let pkgPath; \
try { pkgPath = path.dirname(require.resolve(pkg + '/package.json')); } \
catch(e) { \
  const base = '/app/node_modules/.pnpm'; \
  const {readdirSync} = require('fs'); \
  const prefix = '@libsql+linux-' + arch + '-musl@'; \
  const entry = readdirSync(base).find(d => d.startsWith(prefix)); \
  if (!entry) { console.error('Cannot find', pkg); process.exit(1); } \
  pkgPath = path.join(base, entry, 'node_modules', '@libsql', 'linux-' + arch + '-musl'); \
} \
mkdirSync('/tmp/libsql-native', {recursive: true}); \
cpSync(pkgPath, out, {recursive: true}); \
console.log('Exported', pkg, 'from', pkgPath); \
"

FROM docker.io/library/node:lts-alpine
WORKDIR /app

ARG S6_OVERLAY_VERSION=3.2.0.2
ARG TARGETARCH

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/
RUN set -eu; \
    TA="${TARGETARCH:-}"; \
    [ -n "$TA" ] || case "$(uname -m)" in \
      x86_64) TA=amd64 ;; aarch64|arm64) TA=arm64 ;; \
      *) echo "Unsupported uname -m: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    case "$TA" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) echo "Unsupported arch mapping: ${TA:-empty}" >&2; exit 1 ;; \
    esac; \
    wget -qO "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf "/tmp/s6-overlay-${S6_ARCH}.tar.xz"; \
    rm -f /tmp/s6-overlay-*.tar.xz

COPY --from=build /app/.output /app
COPY --from=build /app/server/database/migrations /app/server/database/migrations
COPY src/phobos-obfuscator/bin /app/phobos/bin
COPY src/server/phobos/templates /app/phobos/templates
RUN apk add --no-cache curl
COPY --from=build /tmp/libsql-native /app/server/node_modules/@libsql/

COPY --from=build /app/cli/cli.sh /usr/local/bin/cli
RUN chmod +x /usr/local/bin/cli

RUN apk add --no-cache \
    dpkg \
    iptables \
    ip6tables \
    nftables \
    kmod \
    iptables-legacy \
    wireguard-go \
    wireguard-tools \
    procps-ng \
    openssl

RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save
RUN update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

RUN ARCH=$(uname -m) && \
    ln -sf /app/phobos/bin/wg-obfuscator-${ARCH} /usr/local/bin/wg-obfuscator && \
    chmod +x /app/phobos/bin/wg-obfuscator-*

COPY docker/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/node/run \
    /etc/s6-overlay/s6-rc.d/node/finish \
    /etc/s6-overlay/s6-rc.d/wg-obfuscator/run \
    /etc/s6-overlay/s6-rc.d/wg-obfuscator/finish

HEALTHCHECK --interval=30s --timeout=8s --start-period=60s --retries=5 CMD \
    /usr/bin/timeout 8s /bin/sh -c \
    'curl -fsSk https://localhost:${PORT:-51831}/ >/dev/null 2>&1 || curl -fsS http://localhost:${PORT:-51831}/ >/dev/null 2>&1'

ENV PORT=51831
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false
ENV DISABLE_IPV6=false
ENV S6_KEEP_ENV=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000

LABEL org.opencontainers.image.source=https://github.com/Ground-Zerro/Phobos

ENTRYPOINT ["/init"]
