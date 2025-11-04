#!/usr/bin/env bash

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE="${LOG_FILE:-/opt/Phobos/logs/${SCRIPT_NAME}.log}"
VERBOSE="${VERBOSE:-0}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -n "${LOG_FILE}" ]] && [[ -d "$(dirname "${LOG_FILE}")" ]]; then
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
  fi

  if [[ ${VERBOSE} -eq 1 ]] || [[ "${level}" == "ERROR" ]] || [[ "${level}" == "WARN" ]]; then
    case "${level}" in
      ERROR)
        echo -e "${RED}[ERROR]${NC} ${message}" >&2
        ;;
      WARN)
        echo -e "${YELLOW}[WARN]${NC} ${message}" >&2
        ;;
      INFO)
        echo -e "${BLUE}[INFO]${NC} ${message}"
        ;;
      SUCCESS)
        echo -e "${GREEN}[SUCCESS]${NC} ${message}"
        ;;
      *)
        echo "[${level}] ${message}"
        ;;
    esac
  fi
}

log_error() {
  log "ERROR" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_info() {
  log "INFO" "$@"
}

log_success() {
  log "SUCCESS" "$@"
}

die() {
  log_error "$@"
  exit 1
}

check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    die "Этот скрипт требует root привилегии. Запустите: sudo $0"
  fi
}

check_command() {
  local cmd="$1"
  local package="${2:-$1}"

  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Команда '${cmd}' не найдена"
    log_info "Установите пакет: apt-get install ${package}"
    return 1
  fi
  return 0
}

check_file() {
  local file="$1"
  local description="${2:-файл}"

  if [[ ! -f "${file}" ]]; then
    log_error "${description} не найден: ${file}"
    return 1
  fi
  return 0
}

check_dir() {
  local dir="$1"
  local description="${2:-директория}"

  if [[ ! -d "${dir}" ]]; then
    log_error "${description} не найдена: ${dir}"
    return 1
  fi
  return 0
}

create_dir() {
  local dir="$1"
  local description="${2:-директория}"

  if [[ ! -d "${dir}" ]]; then
    log_info "Создание ${description}: ${dir}"
    mkdir -p "${dir}" || die "Не удалось создать ${description}: ${dir}"
  fi
}

backup_file() {
  local file="$1"

  if [[ -f "${file}" ]]; then
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Создание резервной копии: ${backup}"
    cp "${file}" "${backup}" || log_warn "Не удалось создать резервную копию"
  fi
}

check_port_available() {
  local port="$1"
  local protocol="${2:-tcp}"

  if ss -${protocol:0:1}lnp | grep -q ":${port} "; then
    log_error "Порт ${port}/${protocol} уже занят"
    ss -${protocol:0:1}lnp | grep ":${port} "
    return 1
  fi
  return 0
}

check_service() {
  local service="$1"

  if ! systemctl is-active --quiet "${service}"; then
    log_error "Сервис ${service} не запущен"
    return 1
  fi
  return 0
}

check_disk_space() {
  local path="$1"
  local required_mb="$2"

  local available_mb=$(df -m "${path}" | awk 'NR==2 {print $4}')

  if [[ ${available_mb} -lt ${required_mb} ]]; then
    log_error "Недостаточно места на диске: ${available_mb}MB доступно, ${required_mb}MB требуется"
    return 1
  fi
  return 0
}

validate_client_name() {
  local name="$1"

  if [[ ! "${name}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Недопустимое имя клиента: ${name}"
    log_info "Имя может содержать только буквы, цифры, дефисы и подчеркивания"
    return 1
  fi

  if [[ ${#name} -lt 3 ]] || [[ ${#name} -gt 32 ]]; then
    log_error "Имя клиента должно быть от 3 до 32 символов"
    return 1
  fi

  return 0
}

validate_ip() {
  local ip="$1"

  if [[ ! "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Недопустимый IP адрес: ${ip}"
    return 1
  fi

  local IFS='.'
  local -a octets=($ip)

  for octet in "${octets[@]}"; do
    if [[ ${octet} -gt 255 ]]; then
      log_error "Недопустимый IP адрес: ${ip}"
      return 1
    fi
  done

  return 0
}

validate_port() {
  local port="$1"

  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    log_error "Недопустимый порт: ${port}"
    return 1
  fi

  if [[ ${port} -lt 1 ]] || [[ ${port} -gt 65535 ]]; then
    log_error "Порт должен быть в диапазоне 1-65535: ${port}"
    return 1
  fi

  return 0
}

retry_command() {
  local max_attempts="$1"
  local delay="$2"
  shift 2
  local cmd="$@"

  local attempt=1

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_info "Попытка ${attempt}/${max_attempts}: ${cmd}"

    if eval "${cmd}"; then
      log_success "Команда выполнена успешно"
      return 0
    fi

    if [[ ${attempt} -lt ${max_attempts} ]]; then
      log_warn "Команда не выполнена, повтор через ${delay} секунд..."
      sleep "${delay}"
    fi

    attempt=$((attempt + 1))
  done

  log_error "Команда не выполнена после ${max_attempts} попыток"
  return 1
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"

  local yn

  if [[ "${default}" == "y" ]]; then
    read -p "${prompt} [Y/n]: " -n 1 -r yn
  else
    read -p "${prompt} [y/N]: " -n 1 -r yn
  fi

  echo ""

  case "${yn}" in
    [Yy]) return 0 ;;
    [Nn]) return 1 ;;
    "")
      [[ "${default}" == "y" ]] && return 0 || return 1
      ;;
    *) return 1 ;;
  esac
}

print_separator() {
  echo "=========================================="
}

print_header() {
  local text="$1"
  print_separator
  echo "  ${text}"
  print_separator
  echo ""
}

cleanup_on_error() {
  local temp_dir="$1"

  if [[ -n "${temp_dir}" ]] && [[ -d "${temp_dir}" ]]; then
    log_info "Очистка временных файлов: ${temp_dir}"
    rm -rf "${temp_dir}"
  fi
}

setup_error_handling() {
  local temp_dir="$1"

  trap "cleanup_on_error '${temp_dir}'" EXIT
  trap "log_error 'Скрипт прерван пользователем'; exit 130" INT TERM
}
