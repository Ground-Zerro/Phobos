#!/bin/sh
set -e

MAX_INTERFACE_NUM=9
NDMC_LAST_ERROR=""

check_dependencies() {
    local missing=""

    for cmd in ndmc date; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        echo "ERROR: Missing required utilities:$missing" >&2
        echo "Please install them using: opkg update && opkg install$missing" >&2
        return 1
    fi

    return 0
}

CLIENT_NAME=""
CLIENT_PRIVATE_KEY=""
CLIENT_IP=""
CLIENT_IPV6=""
SERVER_PUBLIC_KEY=""
CLIENT_PRESHARED_KEY=""
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
  --preshared-key KEY          WireGuard preshared key (required)
  --endpoint-port PORT        Local obfuscator port (default: 13255)
  --keepalive SECONDS         Keepalive interval (default: 25)
  --mtu MTU                   Interface MTU (default: 1420)
  --fallback-config PATH      Path to fallback .conf file
  --help                      Show this help

Example:
  $0 --client-name Pegacomp \\
     --client-private-key "ABCD..." \\
     --client-ip 10.25.0.4 \\
     --client-ipv6 fd00:10:25::4 \\
     --server-public-key "EFGH..." \\
     --preshared-key "BASE64_PSK..." \\
     --endpoint-port 13255 \\
     --fallback-config /opt/etc/Phobos/Pegacomp.conf

EOF
    exit 1
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
            --preshared-key)
                CLIENT_PRESHARED_KEY="$2"
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
       [ -z "${SERVER_PUBLIC_KEY}" ] || [ -z "${CLIENT_PRESHARED_KEY}" ]; then
        error "Missing required parameters"
        usage
    fi
}

ndmc_strip() {
    tr -d '\033' | sed -e 's/\[K//g' -e 's/\r//g'
}

ndmc_run() {
    local output

    if output=$(ndmc -c "$1" 2>&1); then
        NDMC_LAST_ERROR=""
        return 0
    fi

    NDMC_LAST_ERROR=$(printf '%s' "${output}" | ndmc_strip | tr '\n' ' ')
    return 1
}

ndmc_batch() {
    local command

    while IFS= read -r command; do
        [ -n "${command}" ] || continue

        if ! ndmc_run "${command}"; then
            error "ndmc отклонил команду: ${command}"
            [ -n "${NDMC_LAST_ERROR}" ] && error "${NDMC_LAST_ERROR}"
            return 1
        fi
    done

    return 0
}

ndmc_interface_exists() {
    ndmc -c "show interface $1" >/dev/null 2>&1
}

ndmc_interface_description() {
    ndmc -c "show interface $1" 2>/dev/null | ndmc_strip \
        | sed -n 's/^[[:space:]]*description:[[:space:]]*//p' | head -1
}

find_phobos_interface() {
    local client_name="$1"
    local target_desc="Phobos-${client_name}"

    log "Поиск существующего интерфейса Phobos для клиента: ${client_name}..." >&2

    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$(ndmc_interface_description "Wireguard${i}")" = "${target_desc}" ]; then
            log "Найден существующий интерфейс: Wireguard${i}" >&2
            echo "Wireguard${i}"
            return 0
        fi
    done

    log "Существующий интерфейс Phobos не найден" >&2
    echo ""
    return 0
}

find_free_wireguard_interface() {
    log "Поиск свободного интерфейса WireGuard..." >&2

    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if ! ndmc_interface_exists "Wireguard${i}"; then
            log "Найден свободный интерфейс: Wireguard${i}" >&2
            echo "Wireguard${i}"
            return 0
        fi
    done

    error "Нет свободных интерфейсов WireGuard (0-${MAX_INTERFACE_NUM})"
    return 1
}

remove_wireguard_interface() {
    local interface_name="$1"

    log "Удаление существующего интерфейса: ${interface_name}..."

    if ndmc_run "no interface ${interface_name}"; then
        log "Интерфейс ${interface_name} успешно удален ✓"
        return 0
    fi

    log "Предупреждение: не удалось удалить интерфейс: ${NDMC_LAST_ERROR}"
    return 1
}

configure_wireguard_interface() {
    local interface_name="$1"

    local description="Phobos-${CLIENT_NAME}"
    local client_ip_addr=$(echo "${CLIENT_IP}" | cut -d'/' -f1)
    local client_ipv6_block="${CLIENT_IPV6}"

    log "Настройка интерфейса ${interface_name}..."

    ndmc_batch <<EOF || return 1
interface ${interface_name}
interface ${interface_name} description ${description}
interface ${interface_name} security-level public
interface ${interface_name} ip address ${client_ip_addr} 255.255.255.255
interface ${interface_name} ip mtu ${MTU}
interface ${interface_name} ip global 26622
interface ${interface_name} ip tcp adjust-mss pmtu
interface ${interface_name} no ipv6 address auto
interface ${interface_name} ipv6 address ${client_ipv6_block}
interface ${interface_name} no ipv6 prefix auto
interface ${interface_name} wireguard private-key ${CLIENT_PRIVATE_KEY}
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY}
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY} preshared-key ${CLIENT_PRESHARED_KEY}
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY} endpoint 127.0.0.1:${ENDPOINT_PORT}
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY} keepalive-interval ${KEEPALIVE}
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY} allow-ips 0.0.0.0/0
interface ${interface_name} wireguard peer ${SERVER_PUBLIC_KEY} allow-ips ::/0
interface ${interface_name} up
EOF

    log "Интерфейс ${interface_name} создан ✓"

    return 0
}

save_configuration() {
    log "Сохранение конфигурации..."

    if ndmc_run "system configuration save"; then
        log "Конфигурация сохранена ✓"
        return 0
    fi

    error "Ошибка сохранения конфигурации: ${NDMC_LAST_ERROR}"
    return 1
}

verify_interface_created() {
    local client_name="$1"
    local interface_description="Phobos-${client_name}"

    log "Проверка создания интерфейса WireGuard..."

    local found=$(find_phobos_interface "${CLIENT_NAME}")

    if [ -n "$found" ]; then
        log "✓ Интерфейс $found (Phobos-${client_name}) успешно создан"
        return 0
    else
        error "Интерфейс с description '$interface_description' не найден"
        return 1
    fi
}

show_fallback_instructions() {
    cat <<EOF

╔════════════════════════════════════════════════════════════╗
║  Автоматическая настройка не удалась - настройте вручную   ║
╚════════════════════════════════════════════════════════════╝

Конфигурация сохранена в: ${FALLBACK_CONFIG}

Инструкция по ручному импорту:
1. Откройте веб-панель Keenetic (http://192.168.1.1 или http://my.keenetic.net)
2. Перейдите: Интернет → WireGuard
3. Нажмите: 'Добавить подключение'
4. Выберите: 'Загрузить конфигурацию из файла'
5. Укажите путь: ${FALLBACK_CONFIG}
6. Активируйте подключение

EOF
}

main() {
    parse_args "$@"

    if ! check_dependencies; then
        exit 1
    fi

    mkdir -p /opt/etc/Phobos
    log "=== Phobos WireGuard ndmc Configuration ==="
    log "Клиент: ${CLIENT_NAME}"

    EXISTING_INTERFACE=$(find_phobos_interface "${CLIENT_NAME}") || true

    if [ -n "${EXISTING_INTERFACE}" ]; then
        log "Обнаружен существующий интерфейс: ${EXISTING_INTERFACE}"
        if remove_wireguard_interface "${EXISTING_INTERFACE}"; then
            log "Интерфейс ${EXISTING_INTERFACE} удален, будет создан заново"
        else
            log "Не удалось удалить интерфейс ${EXISTING_INTERFACE}, попытка пересоздать"
        fi
    fi

    INTERFACE_NAME=$(find_free_wireguard_interface) || true
    if [ -z "${INTERFACE_NAME}" ]; then
        show_fallback_instructions
        exit 1
    fi
    log "Создание нового интерфейса: ${INTERFACE_NAME}"

    if ! configure_wireguard_interface "${INTERFACE_NAME}"; then
        error "Не удалось настроить WireGuard через ndmc"
        show_fallback_instructions
        exit 1
    fi

    if ! save_configuration; then
        error "Не удалось сохранить конфигурацию"
        exit 1
    fi

    log "Настройка WireGuard завершена успешно! ✓"
    log "Интерфейс: ${INTERFACE_NAME}"
    log "Description: Phobos-${CLIENT_NAME}"

    log ""
    log "Ожидание применения конфигурации..."
    sleep 5

    if verify_interface_created "${CLIENT_NAME}"; then
        log ""
        log "╔════════════════════════════════════════════════════════════╗"
        log "║  WireGuard успешно настроен!                              ║"
        log "╚════════════════════════════════════════════════════════════╝"
        log ""
        exit 0
    else
        log ""
        log "⚠ Не удалось подтвердить создание интерфейса WireGuard"
        log ""
        log "Проверьте вручную в веб-панели Keenetic:"
        log "  Интернет → WireGuard"
        log ""
        exit 1
    fi
}

main "$@"
