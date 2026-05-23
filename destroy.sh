#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/phoboswg}"
COMPOSE_FILE="docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-phoboswg}"
export COMPOSE_PROJECT_NAME

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m  !\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash $0"

if ! command -v docker >/dev/null 2>&1; then
    warn "docker not found — will only clean host files"
    HAS_DOCKER=0
else
    HAS_DOCKER=1
fi

CONTAINER_NAMES=(phobos phobos-caddy phobos-dev)
VOLUME_KEYS_RE='etc_wireguard|sqlite_data|certs_data|acme_data|caddy_data|caddy_config'
VOLUME_RE="(^|_)phobos_(${VOLUME_KEYS_RE})$"
NETWORK_RE='^(phobos|phoboswg)_(wg|default)$'
IMAGE_RE='^(ghcr\.io/)?ground-zerro/phobos(:|@)'

printf '\e[1;31m'
printf '┌─────────────────────────────────────────────┐\n'
printf '│  DESTRUCTIVE OPERATION — NO UNDO POSSIBLE   │\n'
printf '│                                             │\n'
printf '│  Will permanently remove:                   │\n'
printf '│    • PhobosWG containers                    │\n'
printf '│    • PhobosWG Docker volumes                │\n'
printf '│    • PhobosWG Docker networks               │\n'
printf '│    • PhobosWG Docker image                  │\n'
printf '│    • Deploy directory %-21s │\n' "$DEPLOY_DIR"
printf '│    • PhobosWG logs and env files            │\n'
printf '│                                             │\n'
printf '│  Other Docker workloads remain untouched.   │\n'
printf '└─────────────────────────────────────────────┘\n'
printf '\e[0m'
printf '\nType YES to continue: '
read -r CONFIRM
[ "$CONFIRM" = "YES" ] || { warn "Aborted."; exit 0; }

cd /

if [ "$HAS_DOCKER" -eq 1 ]; then
    log "Tearing down compose stack"
    if [ -d "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/$COMPOSE_FILE" ]; then
        if docker compose \
            --project-name "$COMPOSE_PROJECT_NAME" \
            --project-directory "$DEPLOY_DIR" \
            -f "$DEPLOY_DIR/$COMPOSE_FILE" \
            down --volumes --remove-orphans --timeout 15 >/dev/null 2>&1; then
            ok "Compose stack torn down (containers + volumes)"
        else
            warn "compose down failed — falling back to manual cleanup"
        fi
    else
        warn "Compose file not found — skipping compose down"
    fi

    log "Removing PhobosWG containers by name"
    for ctr in "${CONTAINER_NAMES[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -qxF "$ctr"; then
            if docker rm -f "$ctr" >/dev/null 2>&1; then
                ok "Container removed: $ctr"
            else
                warn "Failed to remove container: $ctr"
            fi
        fi
    done

    log "Removing PhobosWG volumes"
    mapfile -t VOLUMES < <(
        docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$VOLUME_RE" || true
    )
    if [ "${#VOLUMES[@]}" -eq 0 ]; then
        warn "No matching volumes found"
    else
        for vol in "${VOLUMES[@]}"; do
            [ -n "$vol" ] || continue
            if docker volume rm "$vol" >/dev/null 2>&1; then
                ok "Volume removed: $vol"
            else
                warn "Failed to remove volume: $vol (in use?)"
            fi
        done
    fi

    log "Removing PhobosWG networks"
    mapfile -t NETS < <(
        docker network ls --format '{{.Name}}' 2>/dev/null | grep -E "$NETWORK_RE" || true
    )
    if [ "${#NETS[@]}" -eq 0 ]; then
        warn "No matching networks found"
    else
        for net in "${NETS[@]}"; do
            [ -n "$net" ] || continue
            if docker network rm "$net" >/dev/null 2>&1; then
                ok "Network removed: $net"
            else
                warn "Failed to remove network: $net"
            fi
        done
    fi

    log "Removing PhobosWG image"
    mapfile -t IMGS < <(
        docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E "$IMAGE_RE" || true
    )
    if [ "${#IMGS[@]}" -eq 0 ]; then
        warn "No PhobosWG image present"
    else
        for img in "${IMGS[@]}"; do
            [ -n "$img" ] || continue
            if docker rmi -f "$img" >/dev/null 2>&1; then
                ok "Image removed: $img"
            else
                warn "Failed to remove image: $img"
            fi
        done
    fi
fi

log "Removing deploy directory: $DEPLOY_DIR"
if [ -d "$DEPLOY_DIR" ]; then
    rm -rf "$DEPLOY_DIR"
    ok "Removed $DEPLOY_DIR"
else
    warn "Deploy directory not present"
fi

log "Removing logs"
for LOG_PATH in /var/log/phoboswg /var/log/phoboswg.log; do
    if [ -e "$LOG_PATH" ]; then
        rm -rf "$LOG_PATH"
        ok "Removed $LOG_PATH"
    fi
done

log "Removing env residuals"
for ENV_FILE in /root/.phoboswg.env /etc/phoboswg.env; do
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        ok "Removed $ENV_FILE"
    fi
done

printf '\n\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  PhobosWG fully removed from this server\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n\n'

if [ "$HAS_DOCKER" -eq 1 ]; then
    REMAINING=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^(phobos|phobos-)' || true)
    if [ -n "$REMAINING" ]; then
        warn "Residual containers still present:"
        printf '    %s\n' $REMAINING
    fi
fi
