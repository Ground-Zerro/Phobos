#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}Ошибка: $1${NC}" >&2
    exit 1
}

log_message() {
    echo -e "${GREEN}$1${NC}"
}

trap 'error_exit "Неожиданная ошибка в строке $LINENO"' ERR

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "Скрипт должен быть запущен с правами root"
    fi
}

install_git() {
    if ! command -v git &> /dev/null; then
        log_message "Git не найден. Установка..."
        if [ -f /etc/debian_version ]; then
            apt-get update -q >/dev/null 2>&1 || error_exit "Не удалось обновить список пакетов"
            apt-get install -y -q git >/dev/null 2>&1 || error_exit "Не удалось установить git"
        else
            error_exit "Неподдерживаемая ОС"
        fi
    fi
}

clone_repository() {
    PHOBOS_BASE_DIR="/opt/Phobos"
    REPO_DIR="$PHOBOS_BASE_DIR/repo"

    if [ -d "$REPO_DIR" ]; then
        log_message "Удаление существующего репозитория..."
        rm -rf "$REPO_DIR"
    fi

    mkdir -p "$REPO_DIR"

    log_message "Клонирование репозитория Phobos..."

    cd "$REPO_DIR"
    git init >/dev/null 2>&1
    git remote add origin https://github.com/Ground-Zerro/Phobos.git >/dev/null 2>&1
    git config core.sparseCheckout true >/dev/null 2>&1

    echo "server" > .git/info/sparse-checkout
    echo "client" >> .git/info/sparse-checkout
    echo "wg-obfuscator" >> .git/info/sparse-checkout

    git pull origin main >/dev/null 2>&1 || error_exit "Не удалось загрузить репозиторий"
    rm -rf .git >/dev/null 2>&1

    find server -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find client -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

    log_message "Репозиторий загружен"
}

prompt_username() {
    echo
    if [ -t 1 ]; then
        exec < /dev/tty
    fi

    while true; do
        read -p "Введите имя первого клиента: " username
        if [ -z "$username" ]; then
            echo "Имя не может быть пустым"
            continue
        fi
        if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "Некорректное имя. Используйте только буквы, цифры, _ и -"
            continue
        fi
        break
    done

    export FIRST_CLIENT="$username"
    log_message "Имя клиента: $username"
}

prompt_obfuscation_level() {
    echo ""
    echo "=========================================="
    echo "    Выберите уровень маскировки трафика"
    echo "=========================================="
    echo ""
    echo "  1) Легкая"
    echo "  2) Достаточная"
    echo "  3) Средняя"
    echo "  4) Выше среднего"
    echo "  5) Кошмар!"
    echo ""

    while true; do
        read -p "Ваш выбор [1-5]: " choice
        case "$choice" in
            1|2|3|4|5)
                export OBF_LEVEL="$choice"
                break
                ;;
            *)
                echo "Некорректный ввод. Введите число от 1 до 5."
                ;;
        esac
    done
}

run_installer() {
    REPO_DIR="/opt/Phobos/repo"
    INSTALLER="$REPO_DIR/server/scripts/phobos-installer.sh"

    if [ ! -f "$INSTALLER" ]; then
        error_exit "Установщик не найден: $INSTALLER"
    fi

    chmod +x "$INSTALLER"
    log_message "Запуск установки Phobos..."
    "$INSTALLER" || error_exit "Ошибка установки"
    log_message "Установка завершена"
}

add_first_client() {
    CLIENT_SCRIPT="/opt/Phobos/repo/server/scripts/phobos-client.sh"

    if [ ! -f "$CLIENT_SCRIPT" ]; then
        error_exit "Скрипт управления клиентами не найден"
    fi

    log_message "Создание клиента $FIRST_CLIENT..."
    "$CLIENT_SCRIPT" add "$FIRST_CLIENT" || error_exit "Ошибка создания клиента"
    log_message "Клиент $FIRST_CLIENT создан"
}

check_root
install_git
clone_repository
prompt_username
prompt_obfuscation_level
run_installer
add_first_client

echo ""
log_message "=========================================="
log_message "  Развертывание Phobos завершено!"
log_message "=========================================="
log_message "Клиент '$FIRST_CLIENT' создан."
log_message "Запустите 'phobos' для управления системой."
echo ""
