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

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

die() {
  log_error "$1"
  exit 1
}

check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    die "Требуются root привилегии. Запустите: sudo $0 $@"
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
