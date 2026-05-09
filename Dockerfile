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
RUN case "$TARGETARCH" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    wget -qO "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" && \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf "/tmp/s6-overlay-${S6_ARCH}.tar.xz" && \
    rm /tmp/s6-overlay-*.tar.xz

COPY --from=build /app/.output /app
COPY --from=build /app/server/database/migrations /app/server/database/migrations
COPY --from=build /app/server/database/bootstrap.sql /app/server/database/bootstrap.sql
COPY src/phobos-obfuscator/bin /app/phobos/bin
COPY src/server/phobos/templates /app/phobos/templates

RUN case "$TARGETARCH" in \
      amd64) PKG="linux-x64-musl" ;; \
      arm64) PKG="linux-arm64-musl" ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac && \
    LIBSQL_VER=$(PKG="$PKG" node -pe "const c=require('/app/server/node_modules/@libsql/client/package.json'); const v=(c.optionalDependencies||{})['@libsql/'+process.env.PKG]; if(!v){process.exit(1)}; v.replace(/^[^0-9]*/, '')") && \
    mkdir -p "/app/server/node_modules/@libsql/$PKG" && \
    wget -qO- "https://registry.npmjs.org/@libsql/$PKG/-/$PKG-$LIBSQL_VER.tgz" \
      | tar xz -C "/app/server/node_modules/@libsql/$PKG" --strip-components=1 && \
    ls /app/server/node_modules/@libsql/

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

LABEL org.opencontainers.image.source=https://github.com/wg-easy/wg-easy

ENTRYPOINT ["/init"]
