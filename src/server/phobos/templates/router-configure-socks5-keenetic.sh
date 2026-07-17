#!/bin/sh
set -e

RCI_URL="http://localhost:79/rci/"
MAX_INTERFACE_NUM=9

check_dependencies() {
    local missing=""

    for cmd in curl jq date; do
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

find_phobos_proxy_interface() {
    local target_desc="Phobos-${CLIENT_NAME}"

    log "Поиск существующего интерфейса Proxy для клиента: ${CLIENT_NAME}..." >&2

    local i
    for i in 0 1 2 3 4 5 6 7 8 9; do
        local interface_json=$(curl -s "${RCI_URL}show/rc/interface/Proxy${i}" 2>/dev/null)

        if [ -n "${interface_json}" ] && echo "${interface_json}" | jq -e . >/dev/null 2>&1; then
            local desc=$(echo "${interface_json}" | jq -r '.description // empty' 2>/dev/null)
            if [ "${desc}" = "${target_desc}" ]; then
                log "Найден существующий интерфейс: Proxy${i}" >&2
                echo "Proxy${i}"
                return 0
            fi
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
        local interface_json=$(curl -s "${RCI_URL}show/interface/Proxy${i}" 2>/dev/null)

        if [ -z "${interface_json}" ] || ! echo "${interface_json}" | jq -e '.id' >/dev/null 2>&1; then
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

    if command -v ndmc >/dev/null 2>&1; then
        if ndmc -c "no interface ${interface_name}" >/dev/null 2>&1; then
            log "Интерфейс ${interface_name} успешно удален ✓"
            return 0
        else
            log "Предупреждение: не удалось удалить интерфейс через ndmc"
            return 1
        fi
    else
        log "Предупреждение: команда ndmc не найдена"
        return 1
    fi
}

configure_proxy_interface() {
    local interface_name="$1"
    local description="Phobos-${CLIENT_NAME}"

    log "Настройка интерфейса ${interface_name}..."

    local commands=$(cat <<EOF
[
  {"parse": "interface ${interface_name}"},
  {"parse": "interface ${interface_name} description ${description}"},
  {"parse": "interface ${interface_name} proxy protocol socks5"},
  {"parse": "interface ${interface_name} proxy socks5-udp"},
  {"parse": "interface ${interface_name} authentication identity ${SOCKS5_LOGIN}"},
  {"parse": "interface ${interface_name} authentication password ${SOCKS5_PASSWORD}"},
  {"parse": "interface ${interface_name} proxy upstream ${UPSTREAM_HOST} ${UPSTREAM_PORT}"},
  {"parse": "interface ${interface_name} no ip name-servers"},
  {"parse": "interface ${interface_name} no ipv6 name-servers"},
  {"parse": "interface ${interface_name} up"},
  {"parse": "interface ${interface_name} ip global 1"}
]
EOF
)

    local result=$(echo "${commands}" | curl -s -X POST \
        -H "Content-Type: application/json" \
        -d @- \
        "${RCI_URL}" 2>/dev/null)

    if echo "${result}" | jq -e '.[] | select(.status == "error")' >/dev/null 2>&1; then
        local error_msg=$(echo "${result}" | jq -r '.[] | select(.status == "error") | .message // "Unknown error"' 2>/dev/null | head -1)
        error "RCI API отклонил конфигурацию: ${error_msg}"
        return 1
    fi

    log "Интерфейс ${interface_name} создан ✓"

    return 0
}

save_configuration() {
    log "Сохранение конфигурации..."

    local result=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"system":{"configuration":{"save":{}}}}' \
        "${RCI_URL}" 2>/dev/null)

    if echo "${result}" | grep -q '"status"[[:space:]]*:[[:space:]]*"message"'; then
        log "Конфигурация сохранена ✓"
        return 0
    else
        error "Ошибка сохранения конфигурации"
        return 1
    fi
}

verify_interface_created() {
    local interface_description="Phobos-${CLIENT_NAME}"

    log "Проверка создания интерфейса Proxy..."

    local interfaces=$(curl -s "http://127.0.0.1:79/rci/show/interface" 2>/dev/null || echo "")

    if [ -z "$interfaces" ]; then
        error "Не удалось получить список интерфейсов через RCI API"
        return 1
    fi

    if ! echo "$interfaces" | jq -e . >/dev/null 2>&1; then
        error "Некорректный JSON ответ от RCI API"
        return 1
    fi

    local found=$(echo "$interfaces" | jq -r "to_entries[] | select(.value.description == \"$interface_description\") | .key" 2>/dev/null)

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
║  RCI API недоступен - требуется ручная настройка          ║
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

    log "=== Phobos SOCKS5 Proxy RCI Configuration ==="
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
        error "Не удалось настроить Proxy через RCI API"
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
