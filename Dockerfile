FROM docker.io/library/node:krypton-alpine AS build
WORKDIR /app

RUN npm install --global corepack@latest
RUN corepack enable pnpm

COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install

COPY src ./
RUN pnpm build

FROM docker.io/library/node:krypton-alpine
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
COPY --from=build /app/server/database/bootstrap.sql /app/server/database/bootstrap.sql
COPY src/phobos-obfuscator/bin /app/phobos/bin
COPY src/server/phobos/templates /app/phobos/templates

RUN set -eux; \
    TA="${TARGETARCH:-}"; \
    [ -n "$TA" ] || case "$(uname -m)" in \
      x86_64) TA=amd64 ;; aarch64|arm64) TA=arm64 ;; \
      *) echo "Unsupported uname -m: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    case "$TA" in \
      amd64) MUSL_PKG=linux-x64-musl; PREFERRED_GNU=linux-x64-gnu ;; \
      arm64) MUSL_PKG=linux-arm64-musl; PREFERRED_GNU=linux-arm64-gnu ;; \
      *) echo "Unsupported TARGETARCH/uname mapping: ${TA:-empty}" >&2; exit 1 ;; \
    esac; \
    LIBSQL_ROOT="/app/server/node_modules/@libsql"; \
    GNU_JSON="${LIBSQL_ROOT}/${PREFERRED_GNU}/package.json"; \
    if [ ! -f "$GNU_JSON" ]; then \
      GNU_JSON="$(find "$LIBSQL_ROOT" -maxdepth 3 -type f -path '*/linux-*-gnu/package.json' 2>/dev/null | head -n1)"; \
    fi; \
    if [ ! -f "$GNU_JSON" ]; then \
      echo "No @libsql linux-*-gnu package.json under $LIBSQL_ROOT" >&2; \
      ls -la "$LIBSQL_ROOT" 2>&1 || true; \
      exit 1; \
    fi; \
    LIBSQL_VER="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).version)" "$GNU_JSON")"; \
    MUSL_TGZ_URL="https://registry.npmjs.org/@libsql/${MUSL_PKG}/-/${MUSL_PKG}-${LIBSQL_VER}.tgz"; \
    mkdir -p "${LIBSQL_ROOT}/${MUSL_PKG}"; \
    wget -O /tmp/libsql-musl.tgz "$MUSL_TGZ_URL" || \
      { echo "wget failed: $MUSL_TGZ_URL (LIBSQL_VER=$LIBSQL_VER from $GNU_JSON)" >&2; exit 1; }; \
    tar -xz -f /tmp/libsql-musl.tgz -C "${LIBSQL_ROOT}/${MUSL_PKG}" --strip-components=1; \
    rm -f /tmp/libsql-musl.tgz; \
    test -f "${LIBSQL_ROOT}/${MUSL_PKG}/package.json" \
      || { echo "Musl unpack failed — no package.json under ${LIBSQL_ROOT}/${MUSL_PKG}" >&2; exit 1; }; \
    ls -la "$LIBSQL_ROOT"/

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
    openssl \
    curl \
    socat

RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save
RUN update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

RUN ARCH=$(uname -m) && \
    ln -sf /app/phobos/bin/wg-obfuscator-${ARCH} /usr/local/bin/wg-obfuscator && \
    chmod +x /app/phobos/bin/wg-obfuscator-*

COPY docker/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/node/run \
    /etc/s6-overlay/s6-rc.d/node/finish \
    /etc/s6-overlay/s6-rc.d/wg-obfuscator/run \
    /etc/s6-overlay/s6-rc.d/wg-obfuscator/finish \
    /etc/s6-overlay/s6-rc.d/acme-renew/run

# procps-ng installs /usr/bin/pgrep (BusyBox only has /bin/pgrep — the old /usr/bin/pgrep path always failed).
HEALTHCHECK --interval=30s --timeout=8s --start-period=120s --retries=5 CMD \
    /usr/bin/timeout 8s /bin/sh -c \
    '/usr/bin/wg show 2>/dev/null | /bin/grep -q interface && /usr/bin/pgrep wg-obfuscator >/dev/null || exit 1'

ENV DEBUG=Server,WireGuard,Database,CMD,Obfuscator,PhobosPackage
ENV PORT=51821
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false
ENV DISABLE_IPV6=false
ENV S6_KEEP_ENV=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000

LABEL org.opencontainers.image.source=https://github.com/Ground-Zerro/Phobos

ENTRYPOINT ["/init"]
