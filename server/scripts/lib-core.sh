#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n\t'

PHOBOS_DIR="/opt/Phobos"
REPO_DIR="$PHOBOS_DIR/repo"
SERVER_ENV="$PHOBOS_DIR/server/server.env"
WG_CONFIG="/etc/wireguard/wg0.conf"
OBF_CONFIG="$PHOBOS_DIR/server/wg-obfuscator.conf"
TOKENS_FILE="$PHOBOS_DIR/tokens/tokens.json"
PACKAGES_DIR="$PHOBOS_DIR/packages"
CLIENTS_DIR="$PHOBOS_DIR/clients"
WWW_DIR="$PHOBOS_DIR/www"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="${LOG_FILE:-}"

_log_to_file() {
  [[ -z "$LOG_FILE" ]] && return
  [[ -d "$(dirname "$LOG_FILE")" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

log_info() {
  _log_to_file "INFO" "$1"
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  _log_to_file "OK" "$1"
  echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
  _log_to_file "WARN" "$1"
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
  _log_to_file "ERROR" "$1"
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

die() {
  log_error "$1"
  exit 1
}

check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    die "Требуются root привилегии. Запустите: sudo $0"
  fi
}

load_env() {
  if [[ -f "$SERVER_ENV" ]]; then
    set +e
    source "$SERVER_ENV"
    set -e
  fi

  export OBFUSCATOR_PORT="${OBFUSCATOR_PORT:-51821}"
  export OBFUSCATOR_KEY="${OBFUSCATOR_KEY:-KEY}"
  export OBFUSCATOR_DUMMY="${OBFUSCATOR_DUMMY:-4}"
  export OBFUSCATOR_IDLE="${OBFUSCATOR_IDLE:-300}"
  export OBFUSCATOR_MASKING="${OBFUSCATOR_MASKING:-AUTO}"
  export WG_LOCAL_ENDPOINT="${WG_LOCAL_ENDPOINT:-127.0.0.1:51820}"
  export TOKEN_TTL="${TOKEN_TTL:-86400}"
  export SERVER_PUBLIC_IP_V4="${SERVER_PUBLIC_IP_V4:-0.0.0.0}"
  export SERVER_PUBLIC_IP_V6="${SERVER_PUBLIC_IP_V6:-}"
  export SERVER_WG_PRIVATE_KEY="${SERVER_WG_PRIVATE_KEY:-}"
  export SERVER_WG_PUBLIC_KEY="${SERVER_WG_PUBLIC_KEY:-}"
  export SERVER_WG_IPV4_NETWORK="${SERVER_WG_IPV4_NETWORK:-10.25.0.0/16}"
  export SERVER_WG_IPV6_NETWORK="${SERVER_WG_IPV6_NETWORK:-fd00:10:25::/48}"
}

ensure_dirs() {
  local dirs=("$PHOBOS_DIR" "$PACKAGES_DIR" "$CLIENTS_DIR" "$WWW_DIR" "$WWW_DIR/init" "$WWW_DIR/packages" "$PHOBOS_DIR/bin" "$PHOBOS_DIR/server" "$PHOBOS_DIR/tokens")
  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done
}

find_free_port() {
  local min=${1:-1024}
  local max=${2:-49151}
  local port
  for _ in {1..100}; do
    port=$((min + RANDOM % (max - min + 1)))
    if ! ss -tlnp | grep -q ":$port " && ! ss -ulnp | grep -q ":$port "; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

get_public_ipv4() {
  local iface
  iface=$(ip route | awk '/^default/{print $5; exit}')
  [[ -z "$iface" ]] && return 1
  local ip
  ip=$(ip -4 addr show dev "$iface" scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1 | head -1)
  [[ -n "$ip" ]] && echo "$ip" && return 0
  return 1
}
