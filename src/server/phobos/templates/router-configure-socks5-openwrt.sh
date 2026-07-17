#!/bin/sh
set -e

CLIENT_NAME=""
OBF_PORT=1080
REDSOCKS_PORT=12345
SOCKS5_LOGIN=""
SOCKS5_PASSWORD=""
SERVER_IP=""
LAN_DEVICE=""
REMOVE=0

REDSOCKS_CONF="/etc/redsocks.conf"
NFT_FILE="/etc/nftables.d/30-phobos-socks5.nft"
REDSOCKS_INIT="/etc/init.d/phobos-redsocks"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    log "ERROR: $*"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --client-name NAME      Client name (required)
  --obf-port PORT         Local obfuscator SOCKS5 port (default: 1080)
  --redsocks-port PORT    Local redsocks listen port (default: 12345)
  --login LOGIN           SOCKS5 auth login (required unless --remove)
  --password PASSWORD     SOCKS5 auth password (required unless --remove)
  --server-ip IP          Upstream server IPv4, excluded from redirect (required unless --remove)
  --lan-device DEV        LAN bridge device (default: auto-detect / br-lan)
  --remove                Tear down redsocks + redirect and exit
  --help                  Show this help
EOF
    exit 1
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --client-name) CLIENT_NAME="$2"; shift 2 ;;
            --obf-port) OBF_PORT="$2"; shift 2 ;;
            --redsocks-port) REDSOCKS_PORT="$2"; shift 2 ;;
            --login) SOCKS5_LOGIN="$2"; shift 2 ;;
            --password) SOCKS5_PASSWORD="$2"; shift 2 ;;
            --server-ip) SERVER_IP="$2"; shift 2 ;;
            --lan-device) LAN_DEVICE="$2"; shift 2 ;;
            --remove) REMOVE=1; shift ;;
            --help) usage ;;
            *) error "Unknown option: $1"; usage ;;
        esac
    done

    if [ "$REMOVE" -eq 1 ]; then
        return 0
    fi

    if [ -z "${CLIENT_NAME}" ] || [ -z "${SOCKS5_LOGIN}" ] || \
       [ -z "${SOCKS5_PASSWORD}" ]; then
        error "Missing required parameters"
        usage
    fi
}

check_dependencies() {
    local missing=""
    for cmd in uci nft; do
        command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
    done
    if [ ! -x /usr/sbin/redsocks ] && ! command -v redsocks >/dev/null 2>&1; then
        missing="$missing redsocks"
    fi
    if [ -n "$missing" ]; then
        error "Missing required utilities:$missing"
        return 1
    fi
    return 0
}

detect_lan_device() {
    if [ -n "$LAN_DEVICE" ]; then
        return 0
    fi
    LAN_DEVICE=$(uci -q get network.lan.device 2>/dev/null)
    [ -n "$LAN_DEVICE" ] || LAN_DEVICE="br-lan"
}

redsocks_bin() {
    if [ -x /usr/sbin/redsocks ]; then
        echo /usr/sbin/redsocks
    else
        command -v redsocks 2>/dev/null || echo /usr/sbin/redsocks
    fi
}

stop_redsocks() {
    [ -x "$REDSOCKS_INIT" ] && "$REDSOCKS_INIT" stop >/dev/null 2>&1 || true
    if [ -x /etc/init.d/redsocks ]; then
        /etc/init.d/redsocks stop >/dev/null 2>&1 || true
        /etc/init.d/redsocks disable >/dev/null 2>&1 || true
    fi
    [ -f /var/run/redsocks.pid ] && kill "$(cat /var/run/redsocks.pid)" 2>/dev/null || true
    pkill -f "$(redsocks_bin)" 2>/dev/null || true
    rm -f /var/run/redsocks.pid 2>/dev/null || true
    sleep 1
}

create_redsocks_init() {
    log "Создание procd-сервиса ${REDSOCKS_INIT}..."
    cat > "$REDSOCKS_INIT" <<EOF
#!/bin/sh /etc/rc.common

START=91
STOP=11

USE_PROCD=1

PROG=$(redsocks_bin)
CONFIG_FILE=${REDSOCKS_CONF}

start_service() {
    [ -f "\$CONFIG_FILE" ] || return 1
    procd_open_instance
    procd_set_param command \$PROG -c \$CONFIG_FILE
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod +x "$REDSOCKS_INIT"
}

port_listening() {
    local port="$1"
    netstat -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]" && return 0
    { command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; }
}

remove_config() {
    log "Удаление конфигурации SOCKS5 (redsocks + nft redirect)..."
    if [ -x "$REDSOCKS_INIT" ]; then
        "$REDSOCKS_INIT" disable >/dev/null 2>&1 || true
    fi
    stop_redsocks
    rm -f "$REDSOCKS_INIT" 2>/dev/null || true
    rm -f "$NFT_FILE" 2>/dev/null || true
    rm -f "$REDSOCKS_CONF" 2>/dev/null || true
    nft delete chain inet fw4 phobos_socks5_dstnat 2>/dev/null || true
    nft delete chain inet fw4 phobos_socks5_input 2>/dev/null || true
    fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1 || true
    log "Конфигурация SOCKS5 удалена"
}

write_redsocks_conf() {
    log "Запись ${REDSOCKS_CONF} (upstream 127.0.0.1:${OBF_PORT})..."
    cat > "$REDSOCKS_CONF" <<EOF
base {
    log_debug = off;
    log_info = off;
    log = "syslog:daemon";
    daemon = off;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = ${REDSOCKS_PORT};
    ip = 127.0.0.1;
    port = ${OBF_PORT};
    type = socks5;
    login = "${SOCKS5_LOGIN}";
    password = "${SOCKS5_PASSWORD}";
}
EOF
    chmod 600 "$REDSOCKS_CONF"
}

resolve_server_exclude() {
    SERVER_EXCLUDE=""
    local ip="$SERVER_IP"
    if ! echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        ip=$(nslookup "$SERVER_IP" 2>/dev/null | awk '/^Address[ :]/{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^127\.' | head -1)
    fi
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        SERVER_EXCLUDE=", ${ip}"
    fi
}

write_nft_redirect() {
    log "Запись nft-редиректа ${NFT_FILE} (LAN ${LAN_DEVICE} TCP → :${REDSOCKS_PORT})..."
    resolve_server_exclude
    mkdir -p /etc/nftables.d
    cat > "$NFT_FILE" <<EOF
chain phobos_socks5_input {
    type filter hook input priority filter - 1; policy accept;
    iifname "${LAN_DEVICE}" tcp dport ${REDSOCKS_PORT} accept
}

chain phobos_socks5_dstnat {
    type nat hook prerouting priority dstnat + 1; policy accept;
    iifname "${LAN_DEVICE}" meta l4proto tcp ip daddr != { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4${SERVER_EXCLUDE} } redirect to :${REDSOCKS_PORT}
}
EOF
}

start_services() {
    log "Запуск redsocks (procd) и применение firewall..."
    "$REDSOCKS_INIT" enable >/dev/null 2>&1 || true
    "$REDSOCKS_INIT" restart >/dev/null 2>&1 || "$REDSOCKS_INIT" start >/dev/null 2>&1 || true
    fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1 || true
}

verify() {
    log "Проверка настройки SOCKS5..."
    local ok=1

    if port_listening "${REDSOCKS_PORT}"; then
        log "redsocks слушает :${REDSOCKS_PORT} ✓"
    else
        error "redsocks не слушает :${REDSOCKS_PORT}"
        ok=0
    fi

    if nft list chain inet fw4 phobos_socks5_dstnat >/dev/null 2>&1; then
        log "nft redirect-правило активно ✓"
    else
        error "nft redirect-правило не найдено"
        ok=0
    fi

    if port_listening "${OBF_PORT}"; then
        log "обфускатор слушает 127.0.0.1:${OBF_PORT} ✓"
    else
        log "ВНИМАНИЕ: не удалось подтвердить обфускатор на :${OBF_PORT} (проверьте init обфускатора)"
    fi

    [ "$ok" -eq 1 ]
}

main() {
    parse_args "$@"

    if [ "$REMOVE" -eq 1 ]; then
        remove_config
        exit 0
    fi

    if ! check_dependencies; then
        exit 1
    fi

    detect_lan_device

    log "=== Phobos SOCKS5 OpenWRT Configuration ==="
    log "Клиент: ${CLIENT_NAME}  ·  LAN: ${LAN_DEVICE}  ·  redsocks :${REDSOCKS_PORT} → obf :${OBF_PORT}"

    stop_redsocks
    write_redsocks_conf
    create_redsocks_init
    write_nft_redirect
    start_services

    sleep 2

    if verify; then
        log ""
        log "SOCKS5 успешно настроен на OpenWRT"
        log "TCP-трафик из LAN (${LAN_DEVICE}) прозрачно идёт через SOCKS5 → сервер"
        log ""
        exit 0
    else
        error "Не удалось подтвердить настройку SOCKS5"
        exit 1
    fi
}

main "$@"
