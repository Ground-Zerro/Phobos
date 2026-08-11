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
UPSTREAM_HOST=""
UPSTREAM_PORT=""
SOCKS5_LOGIN=""
SOCKS5_PASSWORD=""
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
  --client-name NAME     Client name (required)
  --upstream-host HOST   Upstream SOCKS5 host, reachable from NDM (required)
  --upstream-port PORT   Upstream SOCKS5 port (required)
  --login LOGIN          SOCKS5 auth login (required)
  --password PASSWORD    SOCKS5 auth password (required)
  --fallback-config PATH Path to the obfuscator conf shown in manual instructions
  --help                 Show this help

Example:
  $0 --client-name Pegacomp \\
     --upstream-host 127.0.0.1 \\
     --upstream-port 13255 \\
     --login abcde \\
     --password fghij

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
            --upstream-host)
                UPSTREAM_HOST="$2"
                shift 2
                ;;
            --upstream-port)
                UPSTREAM_PORT="$2"
                shift 2
                ;;
            --login)
                SOCKS5_LOGIN="$2"
                shift 2
                ;;
            --password)
                SOCKS5_PASSWORD="$2"
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

    if [ -z "${CLIENT_NAME}" ] || [ -z "${UPSTREAM_HOST}" ] || \
       [ -z "${UPSTREAM_PORT}" ] || [ -z "${SOCKS5_LOGIN}" ] || \
       [ -z "${SOCKS5_PASSWORD}" ]; then
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

find_phobos_proxy_interface() {
    local target_desc="Phobos-${CLIENT_NAME}"

    log "Поиск существующего интерфейса Proxy для клиента: ${CLIENT_NAME}..." >&2

    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if [ "$(ndmc_interface_description "Proxy${i}")" = "${target_desc}" ]; then
            log "Найден существующий интерфейс: Proxy${i}" >&2
            echo "Proxy${i}"
            return 0
        fi
    done

    log "Существующий интерфейс Proxy не найден" >&2
    echo ""
    return 0
}

find_free_proxy_interface() {
    log "Поиск свободного интерфейса Proxy..." >&2

    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if ! ndmc_interface_exists "Proxy${i}"; then
            log "Найден свободный интерфейс: Proxy${i}" >&2
            echo "Proxy${i}"
            return 0
        fi
    done

    error "Нет свободных интерфейсов Proxy (0-${MAX_INTERFACE_NUM})"
    return 1
}

remove_proxy_interface() {
    local interface_name="$1"

    log "Удаление существующего интерфейса: ${interface_name}..."

    if ndmc_run "no interface ${interface_name}"; then
        log "Интерфейс ${interface_name} успешно удален ✓"
        return 0
    fi

    log "Предупреждение: не удалось удалить интерфейс: ${NDMC_LAST_ERROR}"
    return 1
}

configure_proxy_interface() {
    local interface_name="$1"
    local description="Phobos-${CLIENT_NAME}"

    log "Настройка интерфейса ${interface_name}..."

    ndmc_batch <<EOF || return 1
interface ${interface_name}
interface ${interface_name} description ${description}
interface ${interface_name} proxy protocol socks5
interface ${interface_name} proxy socks5-udp
interface ${interface_name} authentication identity ${SOCKS5_LOGIN}
interface ${interface_name} authentication password ${SOCKS5_PASSWORD}
interface ${interface_name} proxy upstream ${UPSTREAM_HOST} ${UPSTREAM_PORT}
interface ${interface_name} no ip name-servers
interface ${interface_name} no ipv6 name-servers
interface ${interface_name} up
interface ${interface_name} ip global 1
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
    local interface_description="Phobos-${CLIENT_NAME}"

    log "Проверка создания интерфейса Proxy..."

    local found=$(find_phobos_proxy_interface)

    if [ -n "$found" ]; then
        log "✓ Интерфейс $found (Phobos-${CLIENT_NAME}) успешно создан"
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

Локальный SOCKS5-обфускатор запущен и настроен в: ${FALLBACK_CONFIG}

Инструкция по ручному созданию интерфейса Proxy:
1. Откройте веб-панель Keenetic (http://192.168.1.1 или http://my.keenetic.net)
2. Перейдите: Интернет → Другие подключения → Добавить подключение
3. Выберите тип: Proxy, протокол SOCKS5
4. Upstream: ${UPSTREAM_HOST}:${UPSTREAM_PORT}
5. Логин/пароль: ${SOCKS5_LOGIN} / ${SOCKS5_PASSWORD}
6. Активируйте подключение

EOF
}

main() {
    parse_args "$@"

    if ! check_dependencies; then
        exit 1
    fi

    log "=== Phobos SOCKS5 Proxy ndmc Configuration ==="
    log "Клиент: ${CLIENT_NAME}"

    EXISTING_INTERFACE=$(find_phobos_proxy_interface) || true

    if [ -n "${EXISTING_INTERFACE}" ]; then
        log "Обнаружен существующий интерфейс: ${EXISTING_INTERFACE}"
        if remove_proxy_interface "${EXISTING_INTERFACE}"; then
            log "Интерфейс ${EXISTING_INTERFACE} удален, будет создан заново"
        else
            log "Не удалось удалить интерфейс ${EXISTING_INTERFACE}, попытка пересоздать"
        fi
    fi

    INTERFACE_NAME=$(find_free_proxy_interface) || true
    if [ -z "${INTERFACE_NAME}" ]; then
        show_fallback_instructions
        exit 1
    fi
    log "Создание нового интерфейса: ${INTERFACE_NAME}"

    if ! configure_proxy_interface "${INTERFACE_NAME}"; then
        error "Не удалось настроить Proxy через ndmc"
        show_fallback_instructions
        exit 1
    fi

    if ! save_configuration; then
        error "Не удалось сохранить конфигурацию"
        exit 1
    fi

    log "Настройка SOCKS5 Proxy завершена успешно! ✓"
    log "Интерфейс: ${INTERFACE_NAME}"
    log "Description: Phobos-${CLIENT_NAME}"

    log ""
    log "Ожидание применения конфигурации..."
    sleep 3

    if verify_interface_created; then
        log ""
        log "╔════════════════════════════════════════════════════════════╗"
        log "║  SOCKS5 Proxy успешно настроен!                            ║"
        log "╚════════════════════════════════════════════════════════════╝"
        log ""
        exit 0
    else
        log ""
        log "⚠ Не удалось подтвердить создание интерфейса Proxy"
        log ""
        log "Проверьте вручную в веб-панели Keenetic:"
        log "  Интернет → Другие подключения"
        log ""
        exit 1
    fi
}

main "$@"
