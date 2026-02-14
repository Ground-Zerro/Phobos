#!/bin/sh
set -e

CLIENT_NAME=""
CLIENT_PRIVATE_KEY=""
CLIENT_IP=""
CLIENT_IPV6=""
SERVER_PUBLIC_KEY=""
ENDPOINT_PORT=13255
KEEPALIVE=25
MTU=1420
FALLBACK_CONFIG=""

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
  --client-name NAME          Client name (required)
  --client-private-key KEY    WireGuard private key (required)
  --client-ip IP              Client tunnel IPv4 address (required)
  --client-ipv6 IP            Client tunnel IPv6 address (required)
  --server-public-key KEY     Server WireGuard public key (required)
  --endpoint-port PORT        Local obfuscator port (default: 13255)
  --keepalive SECONDS         Keepalive interval (default: 25)
  --mtu MTU                   Interface MTU (default: 1420)
  --fallback-config PATH      Path to fallback .conf file
  --help                      Show this help

Example:
  $0 --client-name home \\
     --client-private-key "ABCD..." \\
     --client-ip 10.25.0.4/32 \\
     --client-ipv6 fd00:10:25::4/128 \\
     --server-public-key "EFGH..." \\
     --endpoint-port 13255 \\
     --fallback-config /opt/etc/Phobos/home.conf

EOF
    exit 1
}

check_dependencies() {
    local missing=""

    for cmd in uci wg; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        error "Missing required utilities:$missing"
        return 1
    fi

    return 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --client-name)
                CLIENT_NAME="$2"
                shift 2
                ;;
            --client-private-key)
                CLIENT_PRIVATE_KEY="$2"
                shift 2
                ;;
            --client-ip)
                CLIENT_IP="$2"
                shift 2
                ;;
            --client-ipv6)
                CLIENT_IPV6="$2"
                shift 2
                ;;
            --server-public-key)
                SERVER_PUBLIC_KEY="$2"
                shift 2
                ;;
            --endpoint-port)
                ENDPOINT_PORT="$2"
                shift 2
                ;;
            --keepalive)
                KEEPALIVE="$2"
                shift 2
                ;;
            --mtu)
                MTU="$2"
                shift 2
                ;;
            --fallback-config)
                FALLBACK_CONFIG="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [ -z "${CLIENT_NAME}" ] || [ -z "${CLIENT_PRIVATE_KEY}" ] || \
       [ -z "${CLIENT_IP}" ] || [ -z "${CLIENT_IPV6}" ] || \
       [ -z "${SERVER_PUBLIC_KEY}" ]; then
        error "Missing required parameters"
        usage
    fi
}

check_existing_interface() {
    local interface_name="phobos_wg"

    if uci -q get network.${interface_name} >/dev/null 2>&1; then
        log "Найден существующий интерфейс: ${interface_name}"
        return 0
    else
        log "Существующий интерфейс Phobos не найден"
        return 1
    fi
}

remove_existing_interface() {
    local interface_name="phobos_wg"

    log "Удаление существующего интерфейса ${interface_name}..."

    uci -q delete network.${interface_name} || true

    local peers=$(uci show network | grep "wireguard_${interface_name}" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u)
    for peer in $peers; do
        uci -q delete network.$peer || true
    done

    uci commit network
    log "Существующий интерфейс удален"
}

configure_wireguard_interface() {
    local interface_name="phobos_wg"

    log "Настройка интерфейса ${interface_name} через UCI..."

    uci set network.${interface_name}=interface
    uci set network.${interface_name}.proto='wireguard'
    uci set network.${interface_name}.private_key="${CLIENT_PRIVATE_KEY}"
    uci set network.${interface_name}.mtu="${MTU}"

    uci add_list network.${interface_name}.addresses="${CLIENT_IP}"

    if [ "${CLIENT_IPV6}" != "none" ] && [ -n "${CLIENT_IPV6}" ]; then
        uci add_list network.${interface_name}.addresses="${CLIENT_IPV6}"
    fi

    local peer_name="wgpeer_${interface_name}"
    uci add network wireguard_${interface_name}
    uci rename network.@wireguard_${interface_name}[-1]="${peer_name}"
    uci set network.${peer_name}.public_key="${SERVER_PUBLIC_KEY}"
    uci set network.${peer_name}.description="Phobos VPS Server"
    uci set network.${peer_name}.endpoint_host='127.0.0.1'
    uci set network.${peer_name}.endpoint_port="${ENDPOINT_PORT}"
    uci set network.${peer_name}.persistent_keepalive="${KEEPALIVE}"
    uci set network.${peer_name}.route_allowed_ips='0'

    uci add_list network.${peer_name}.allowed_ips='0.0.0.0/0'
    uci add_list network.${peer_name}.allowed_ips='::/0'

    uci commit network

    log "Интерфейс ${interface_name} настроен ✓"
    return 0
}

configure_firewall_zone() {
    local zone_name="phobos"
    local interface_name="phobos_wg"

    log "Настройка файрволла для зоны ${zone_name}..."

    if uci -q get firewall.${zone_name} >/dev/null 2>&1; then
        log "Зона ${zone_name} уже существует, обновляем..."
        uci delete firewall.${zone_name}
    fi

    uci add firewall zone
    uci rename firewall.@zone[-1]="${zone_name}"
    uci set firewall.${zone_name}.name="${zone_name}"
    uci add_list firewall.${zone_name}.network="${interface_name}"
    uci set firewall.${zone_name}.input='REJECT'
    uci set firewall.${zone_name}.output='ACCEPT'
    uci set firewall.${zone_name}.forward='REJECT'
    uci set firewall.${zone_name}.masq='0'
    uci set firewall.${zone_name}.mtu_fix='1'

    uci commit firewall

    log "Файрволл зона ${zone_name} настроена ✓"
    return 0
}

restart_network_services() {
    log "Перезапуск сетевых сервисов..."

    /etc/init.d/network reload >/dev/null 2>&1 || true
    sleep 3

    ifup phobos_wg >/dev/null 2>&1 || true
    sleep 2

    /etc/init.d/firewall reload >/dev/null 2>&1 || true
    sleep 1

    log "Сетевые сервисы перезапущены ✓"
}

verify_interface_created() {
    log "Проверка создания интерфейса WireGuard..."
    
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ip link show phobos_wg >/dev/null 2>&1; then
            log "Интерфейс phobos_wg найден (попытка $attempt/$max_attempts)"
            
            if wg show phobos_wg >/dev/null 2>&1; then
                log "WireGuard интерфейс phobos_wg активен"
                
                if uci -q get network.phobos_wg >/dev/null 2>&1; then
                    log "UCI конфигурация phobos_wg найдена"
                    return 0
                else
                    log "UCI конфигурация phobos_wg не найдена, но интерфейс работает"
                    return 0
                fi
            else
                log "Интерфейс найден, но WireGuard не активен (попытка $attempt/$max_attempts)"
            fi
        else
            log "Интерфейс phobos_wg еще не создан (попытка $attempt/$max_attempts)..."
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    error "Интерфейс phobos_wg не найден после $max_attempts попыток"
    return 1
}

show_fallback_instructions() {
    cat <<EOF

╔═══════════════════════════════════════════════════════════╗
║  Требуется ручная настройка WireGuard                     ║
╚═══════════════════════════════════════════════════════════╝

Конфигурация сохранена в: ${FALLBACK_CONFIG}

Инструкция по ручной настройке:
1. Установите пакеты: opkg install kmod-wireguard wireguard-tools wireguard-tools
2. Импортируйте конфигурацию из ${FALLBACK_CONFIG}
3. Настройте интерфейс через UCI или LuCI веб-интерфейс

EOF
}

main() {
    parse_args "$@"

    if ! check_dependencies; then
        show_fallback_instructions
        exit 1
    fi

    log "=== Phobos WireGuard OpenWRT Configuration ==="
    log "Клиент: ${CLIENT_NAME}"

    if check_existing_interface; then
        remove_existing_interface
    fi

    if ! configure_wireguard_interface; then
        error "Не удалось настроить WireGuard через UCI"
        show_fallback_instructions
        exit 1
    fi

    if ! configure_firewall_zone; then
        error "Не удалось настроить файрволл"
        exit 1
    fi

    restart_network_services

    log ""
    log "Ожидание применения конфигурации..."
    sleep 5

    if verify_interface_created; then
        log ""
        log "WireGuard успешно настроен на OpenWRT"
        log ""
        log "Интерфейс: phobos_wg"
        log "Файрволл зона: phobos (без форвардинга)"
        log ""
        log "Для маршрутизации трафика через туннель настройте правила"
        log "файрволла и маршрутизацию вручную через LuCI или UCI."
        log ""
        
        log "Текущий статус интерфейса:"
        ip addr show phobos_wg 2>/dev/null | sed 's/^/  /' || true
        log ""
        
        exit 0
    else
        log ""
        log "Не удалось подтвердить создание интерфейса WireGuard"
        log ""
        log "Проверьте вручную:"
        log "  ip link show phobos_wg"
        log "  wg show phobos_wg"
        log "  uci show network.phobos_wg"
        log ""
        log "Если интерфейс существует (ip link show phobos_wg работает),"
        log "то настройка прошла успешно, несмотря на ошибку проверки."
        log ""
        exit 1
    fi
}

main "$@"