#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/phoboswg}"
UI_PORT="${UI_PORT:-51831}"
WG_HOST="${WG_HOST:-}"
WG_EASY_IMAGE="${WG_EASY_IMAGE:-ghcr.io/ground-zerro/phobos:latest}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/Ground-Zerro/Phobos/main}"
COMPOSE_FILE="docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-phoboswg}"
export COMPOSE_PROJECT_NAME
INIT_ENABLED="${INIT_ENABLED:-false}"
INIT_USERNAME="${INIT_USERNAME:-admin}"
INIT_PASSWORD="${INIT_PASSWORD:-}"
WATCHDOG_PID=""
WATCHDOG_LOG="/var/log/phoboswg-deploy-watchdog.log"

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %b\n' "$*" >&2; exit 1; }
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

ensure_json_tools() {
  log "Installing/updating jq and python3"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq jq python3 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y jq python3 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq python3 || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --upgrade jq python3 || true
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install jq python3 || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -S --noconfirm --needed jq python3 || true
  fi
  local jq_ver py_ver
  jq_ver="$(jq --version 2>/dev/null || echo absent)"
  py_ver="$(python3 --version 2>/dev/null || echo absent)"
  if [ "$jq_ver" = "absent" ] && [ "$py_ver" = "absent" ]; then
    log "Warning: could not install jq or python3 — daemon.json merge will be skipped if the file already exists"
  else
    ok "JSON tools: jq ${jq_ver}, ${py_ver}"
  fi
}

configure_docker_daemon() {
  local daemon_json="/etc/docker/daemon.json"
  if [ -f "$daemon_json" ] && grep -q '"userland-proxy"' "$daemon_json"; then
    ok "Docker userland-proxy already configured"
    return
  fi
  mkdir -p /etc/docker
  if [ ! -f "$daemon_json" ]; then
    printf '{\n  "userland-proxy": false\n}\n' > "$daemon_json"
  elif command -v jq >/dev/null 2>&1; then
    local tmp_json
    tmp_json="$(mktemp)"
    jq '. + {"userland-proxy": false}' "$daemon_json" > "$tmp_json"
    mv "$tmp_json" "$daemon_json"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$daemon_json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["userland-proxy"] = False
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  else
    log "Warning: ${daemon_json} exists and neither jq nor python3 is available — userland-proxy stays enabled (expect one docker-proxy process per published port)"
    return
  fi
  chmod 644 "$daemon_json"
  log "Restarting Docker to disable userland-proxy (this stack publishes ~200 ports)"
  systemctl restart docker
  ok "Docker userland-proxy disabled"
}

fix_networkd_docker_bridge() {
  systemctl is-active --quiet systemd-networkd || return 0
  local net_drop="/etc/systemd/network/05-docker-unmanaged.network"
  local new_content="[Match]
Name=veth* docker0 br-*

[Link]
Unmanaged=yes"
  if [ "$(cat "$net_drop" 2>/dev/null)" = "$new_content" ]; then
    ok "systemd-networkd docker bridge fix already applied"
    return
  fi
  printf '%s\n' "$new_content" > "$net_drop"
  if networkctl reload 2>/dev/null; then
    ok "systemd-networkd configured to ignore docker bridges"
  else
    log "Warning: 'networkctl reload' unavailable — drop-in written, takes effect on next boot or interface event"
  fi
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

start_load_watchdog() {
  local nproc_count threshold trigger_count interval
  nproc_count="$(nproc)"
  threshold="$(awk -v n="$nproc_count" 'BEGIN { t = n * 2; if (t < 6) t = 6; printf "%.2f", t }')"
  trigger_count="${WATCHDOG_TRIGGER_COUNT:-5}"
  interval="${WATCHDOG_INTERVAL_SEC:-5}"
  (
    exec >>"$WATCHDOG_LOG" 2>&1
    hits=0
    printf '[%s] watchdog armed: threshold=%s (nproc=%s), interval=%ss, trigger=%s consecutive samples\n' \
      "$(date -Is)" "$threshold" "$nproc_count" "$interval" "$trigger_count"
    while :; do
      sleep "$interval"
      load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
      [ -n "$load1" ] || continue
      if [ "$(awk -v l="$load1" -v t="$threshold" 'BEGIN { print (l > t) ? 1 : 0 }')" = "1" ]; then
        hits=$((hits + 1))
        printf '[%s] load %s over threshold %s (%s/%s)\n' "$(date -Is)" "$load1" "$threshold" "$hits" "$trigger_count"
      else
        hits=0
      fi
      if [ "$hits" -ge "$trigger_count" ]; then
        printf '[%s] sustained overload: load %s > %s for ~%ss — tearing down stack\n' \
          "$(date -Is)" "$load1" "$threshold" "$((trigger_count * interval))"
        docker compose -f "${DEPLOY_DIR}/${COMPOSE_FILE}" down --timeout 5 || true
        printf '[%s] stack torn down by watchdog\n' "$(date -Is)"
        exit 0
      fi
    done
  ) &
  WATCHDOG_PID=$!
  chrt -f -p 10 "$WATCHDOG_PID" 2>/dev/null || renice -n -15 -p "$WATCHDOG_PID" >/dev/null 2>&1 || true
  log "Load watchdog armed (threshold ${threshold}, log: ${WATCHDOG_LOG})"
}

stop_load_watchdog() {
  if [ -n "$WATCHDOG_PID" ] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
  fi
}
trap stop_load_watchdog EXIT

rollback_stack() {
  log "Rolling back: stopping and removing the stack so no crash-looping container is left unattended"
  docker compose -f "$COMPOSE_FILE" down --timeout 15 >/dev/null 2>&1 || true
}

wait_healthy() {
  local ctr="${WAIT_HEALTHY_CONTAINER:-phobos}"
  local poll_s="${WAIT_HEALTHY_POLL_SEC:-2}"
  local timeout_s="${WAIT_HEALTHY_TIMEOUT_SEC:-360}"
  local start_ts now_ts elapsed i=0 status ctr_logs
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
        ctr_logs="$(docker logs --tail 120 "${ctr}" 2>/dev/null || true)"
        rollback_stack
        fail "Container reported unhealthy after ${elapsed}s. Logs:\n${ctr_logs}"
        ;;
      missing)
        rollback_stack
        fail "Container is missing (if the load watchdog tore it down, see ${WATCHDOG_LOG})"
        ;;
      *)
        if [ $((i % 5)) -eq 0 ]; then
          printf '    status=%s elapsed=%ss/%ss\n' "${status}" "${elapsed}" "${timeout_s}"
        fi
        ;;
    esac

    if [ "${elapsed}" -ge "${timeout_s}" ]; then
      ctr_logs="$(docker logs --tail 150 "${ctr}" 2>/dev/null || true)"
      rollback_stack
      fail "Container did not become healthy in ${timeout_s}s (last status: ${status}). Logs:\n${ctr_logs}"
    fi

    i=$((i + 1))
    sleep "${poll_s}"
  done
}

require_root
ensure_docker
ensure_json_tools
configure_docker_daemon
fix_networkd_docker_bridge
load_wireguard_module

if [ -z "$WG_HOST" ]; then
  log "Detecting public IP"
  WG_HOST="$(detect_public_ip)"
  ok "Public IP: $WG_HOST"
fi

if [ "$INIT_ENABLED" = "true" ] && [ -z "$INIT_PASSWORD" ]; then
  INIT_PASSWORD="$(random_password)"
fi

download_stack_files
cd "$DEPLOY_DIR"

log "Writing .env"
if [ "$INIT_ENABLED" = "true" ]; then
  cat > "${DEPLOY_DIR}/.env" <<EOF
WG_HOST=${WG_HOST}
WG_EASY_IMAGE=${WG_EASY_IMAGE}
INIT_ENABLED=true
INIT_USERNAME=${INIT_USERNAME}
INIT_PASSWORD=${INIT_PASSWORD}
INIT_HOST=${WG_HOST}
EOF
else
  cat > "${DEPLOY_DIR}/.env" <<EOF
WG_HOST=${WG_HOST}
WG_EASY_IMAGE=${WG_EASY_IMAGE}
INIT_ENABLED=false
EOF
fi
ok ".env written"

log "Pulling image"
docker compose -f "$COMPOSE_FILE" pull
ok "Image pulled"

start_load_watchdog

log "Starting stack (compose=$COMPOSE_FILE)"
docker compose -f "$COMPOSE_FILE" up -d --force-recreate
ok "Stack started"

wait_healthy
stop_load_watchdog

printf '\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  PhobosWG deployed successfully\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\n'

if [ "$INIT_ENABLED" = "true" ]; then
  printf '\e[1;33m  >>> Open in browser to log in: <<<\e[0m\n'
  printf '\e[1;37m  http://%s:%s/\e[0m\n' "$WG_HOST" "$UI_PORT"
  printf '\n'
  printf '  Username    : %s\n' "$INIT_USERNAME"
  printf '  Password    : %s\n' "$INIT_PASSWORD"
  printf '\n'
  printf '\e[0;33m  Note: to configure domain and TLS certificate go to\e[0m\n'
  printf '\e[0;33m  Admin → Interface after login.\e[0m\n'
  printf '\e[0;33m  Credentials above apply on first deploy only (new database).\e[0m\n'
else
  printf '\e[1;33m  >>> Open in browser to complete initial setup: <<<\e[0m\n'
  printf '\e[1;37m  http://%s:%s/\e[0m\n' "$WG_HOST" "$UI_PORT"
  printf '\n'
  printf '  The setup wizard will guide you through:\n'
  printf '    1. Create admin account (username + password)\n'
  printf '    2. Set server host (IP address or domain name)\n'
  printf '    3. Configure TLS certificate (self-signed / import / skip)\n'
fi

printf '\n'
printf '  Admin UI    : %s:%s\n' "$WG_HOST" "$UI_PORT"
printf '  Obfuscator  : UDP/TCP %s:51822-51921 (preset range)\n' "$WG_HOST"
printf '  Image       : %s\n' "$WG_EASY_IMAGE"
printf '  Deploy dir  : %s\n' "$DEPLOY_DIR"
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\n'
docker ps --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"
printf '\n'
