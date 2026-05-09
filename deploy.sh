#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/wg-easy}"
OBF_PORT="${OBF_PORT:-51822}"
WG_HOST="${WG_HOST:-}"
WG_EASY_IMAGE="${WG_EASY_IMAGE:-ghcr.io/ground-zerro/phobos:latest}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/Ground-Zerro/Phobos/ph-wg-easy}"
COMPOSE_FILE="docker-compose.yml"
INIT_ENABLED="${INIT_ENABLED:-true}"
INIT_USERNAME="${INIT_USERNAME:-admin}"
INIT_PASSWORD="${INIT_PASSWORD:-}"

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
trap 'printf "\e[1;31mERROR:\e[0m Deploy failed at line %s\n" "$LINENO" >&2' ERR

require_root() {
  [ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash $0"
}

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

random_password() {
  local prev_pipefail password
  prev_pipefail="$(set -o | awk '$1=="pipefail"{print $2}')"
  set +o pipefail
  password="$(tr -dc 'A-Za-z0-9!@#%^*_+=' < /dev/urandom | head -c 20 || true)"
  if [ "$prev_pipefail" = "on" ]; then
    set -o pipefail
  fi
  [ -n "$password" ] || password="Phobos$(date +%s)Aa1!"
  printf '%s' "$password"
}

install_docker() {
  log "Installing Docker"
  local distro
  distro="$(detect_distro)"

  case "$distro" in
    ubuntu|debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq ca-certificates curl
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL "https://download.docker.com/linux/${distro}/gpg" -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
      apt-get update -qq
      apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    centos|rhel|fedora|rocky|almalinux)
      dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      curl -fsSL https://get.docker.com | sh
      ;;
  esac

  systemctl enable --now docker
  ok "Docker installed: $(docker --version)"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker already present: $(docker --version)"
    return
  fi
  install_docker
}

load_wireguard_module() {
  if lsmod | grep -q wireguard 2>/dev/null; then
    ok "WireGuard kernel module already loaded"
    return
  fi
  if modprobe wireguard 2>/dev/null; then
    ok "WireGuard kernel module loaded"
  else
    log "Warning: could not load wireguard module — wireguard-go (userspace) will be used"
  fi
}

detect_public_ip() {
  local ip
  ip=$(
    curl -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null ||
    curl -fsSL --connect-timeout 5 https://ifconfig.me 2>/dev/null ||
    curl -fsSL --connect-timeout 5 https://icanhazip.com 2>/dev/null ||
    true
  )
  echo "${ip:-127.0.0.1}"
}

download_stack_files() {
  log "Downloading deployment files"
  mkdir -p "$DEPLOY_DIR"
  curl -fsSL "${REPO_RAW_BASE}/docker-compose.yml" -o "${DEPLOY_DIR}/docker-compose.yml"
  ok "docker-compose.yml downloaded"
}

wait_healthy() {
  local ctr="${WAIT_HEALTHY_CONTAINER:-wg-easy}"
  local poll_s="${WAIT_HEALTHY_POLL_SEC:-2}"
  local timeout_s="${WAIT_HEALTHY_TIMEOUT_SEC:-360}"
  local start_ts now_ts elapsed i=0 status
  start_ts=$(date +%s)

  log "Waiting for container ${ctr} (poll ${poll_s}s, timeout ${timeout_s}s)"
  while :; do
    status=$(docker inspect "${ctr}" --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}nohealth{{end}}" 2>/dev/null || echo "missing")
    now_ts=$(date +%s)
    elapsed=$((now_ts - start_ts))

    case "$status" in
      healthy)
        ok "Container is healthy after ${elapsed}s"
        docker ps --filter "name=${ctr}" --format "  {{.Names}} | {{.Status}} | {{.Ports}}"
        return 0
        ;;
      unhealthy)
        fail "Container reported unhealthy after ${elapsed}s. Logs:\n$(docker logs --tail 120 "${ctr}" 2>/dev/null || true)"
        ;;
      missing)
        fail "Container is missing"
        ;;
      *)
        if [ $((i % 5)) -eq 0 ]; then
          printf '    status=%s elapsed=%ss/%ss\n' "${status}" "${elapsed}" "${timeout_s}"
        fi
        ;;
    esac

    if [ "${elapsed}" -ge "${timeout_s}" ]; then
      fail "Container did not become healthy in ${timeout_s}s (last status: ${status}). Logs:\n$(docker logs --tail 150 "${ctr}" 2>/dev/null || true)"
    fi

    i=$((i + 1))
    sleep "${poll_s}"
  done
}

require_root
ensure_docker
load_wireguard_module

if [ -z "$WG_HOST" ]; then
  log "Detecting public IP"
  WG_HOST="$(detect_public_ip)"
  ok "Public IP: $WG_HOST"
fi

if [ -z "$INIT_PASSWORD" ]; then
  INIT_PASSWORD="$(random_password)"
fi

download_stack_files
cd "$DEPLOY_DIR"

log "Writing .env"
cat > "${DEPLOY_DIR}/.env" <<EOF
WG_HOST=${WG_HOST}
OBF_PORT=${OBF_PORT}
WG_EASY_IMAGE=${WG_EASY_IMAGE}
INIT_ENABLED=${INIT_ENABLED}
INIT_USERNAME=${INIT_USERNAME}
INIT_PASSWORD=${INIT_PASSWORD}
INIT_HOST=${WG_HOST}
EOF
ok ".env written"

log "Pulling image"
docker compose -f "$COMPOSE_FILE" pull
ok "Image pulled"

log "Starting stack (compose=$COMPOSE_FILE, OBF_PORT=$OBF_PORT)"
OBF_PORT="$OBF_PORT" docker compose -f "$COMPOSE_FILE" up -d --force-recreate
ok "Stack started"

wait_healthy

printf '\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  wg-easy deployed successfully\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '  Web UI      : http://%s:51821/\n' "$WG_HOST"
printf '  Obfuscator  : UDP %s:%s\n' "$WG_HOST" "$OBF_PORT"
printf '  Username    : %s\n' "$INIT_USERNAME"
printf '  Password    : %s\n' "$INIT_PASSWORD"
printf '  Image       : %s\n' "$WG_EASY_IMAGE"
printf '  Deploy dir  : %s\n' "$DEPLOY_DIR"
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\n'
printf 'Credentials are applied on first setup only (new database).\n\n'
docker ps --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"
printf '\n'
