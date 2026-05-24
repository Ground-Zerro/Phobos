#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/phoboswg}"
COMPOSE_FILE="docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-phoboswg}"
export COMPOSE_PROJECT_NAME

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
info() { printf '\e[1;30m  ·\e[0m %s\n' "$*"; }
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
VOLUME_KEYS_RE='etc_wireguard|sqlite_data|certs_data|caddy_data|caddy_config'
VOLUME_RE="(^|_)phobos_(${VOLUME_KEYS_RE})$"
NETWORK_RE='^(phobos|phoboswg)_(wg|default)$'
IMAGE_RE='^(ghcr\.io/)?ground-zerro/phobos(:|@)'

# Set when `compose down --volumes --remove-orphans` succeeded — subsequent
# manual cleanup steps then expect to find nothing left, so "no match" is
# informational rather than a warning.
COMPOSE_CLEAN=0

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
            ok "Compose stack torn down (containers + volumes + network)"
            COMPOSE_CLEAN=1
        else
            warn "compose down failed — falling back to manual cleanup"
        fi
    else
        info "Compose file not found at $DEPLOY_DIR/$COMPOSE_FILE — skipping compose down"
    fi

    log "Removing PhobosWG containers by name"
    REMOVED_CT=0
    for ctr in "${CONTAINER_NAMES[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -qxF "$ctr"; then
            if docker rm -f "$ctr" >/dev/null 2>&1; then
                ok "Container removed: $ctr"
                REMOVED_CT=$((REMOVED_CT + 1))
            else
                warn "Failed to remove container: $ctr"
            fi
        fi
    done
    if [ "$REMOVED_CT" -eq 0 ]; then
        if [ "$COMPOSE_CLEAN" -eq 1 ]; then
            info "No residual containers (compose already removed them)"
        else
            info "No matching containers found"
        fi
    fi

    log "Removing PhobosWG volumes"
    mapfile -t VOLUMES < <(
        docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$VOLUME_RE" || true
    )
    if [ "${#VOLUMES[@]}" -eq 0 ]; then
        if [ "$COMPOSE_CLEAN" -eq 1 ]; then
            info "No residual volumes (compose already removed them)"
        else
            warn "No matching volumes found"
        fi
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
        if [ "$COMPOSE_CLEAN" -eq 1 ]; then
            info "No residual networks (compose already removed them)"
        else
            warn "No matching networks found"
        fi
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
        info "No PhobosWG image present"
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
    info "Deploy directory not present"
fi

log "Removing logs"
LOG_REMOVED=0
for LOG_PATH in /var/log/phoboswg /var/log/phoboswg.log; do
    if [ -e "$LOG_PATH" ]; then
        rm -rf "$LOG_PATH"
        ok "Removed $LOG_PATH"
        LOG_REMOVED=$((LOG_REMOVED + 1))
    fi
done
[ "$LOG_REMOVED" -eq 0 ] && info "No PhobosWG logs found"

log "Removing env residuals"
ENV_REMOVED=0
for ENV_FILE in /root/.phoboswg.env /etc/phoboswg.env; do
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        ok "Removed $ENV_FILE"
        ENV_REMOVED=$((ENV_REMOVED + 1))
    fi
done
[ "$ENV_REMOVED" -eq 0 ] && info "No env residuals found"

printf '\n\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  PhobosWG fully removed from this server\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n\n'

if [ "$HAS_DOCKER" -eq 1 ]; then
    REMAINING_CT=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^(phobos$|phobos-)' || true)
    REMAINING_VOL=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$VOLUME_RE" || true)
    REMAINING_NET=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E "$NETWORK_RE" || true)

    if [ -n "$REMAINING_CT" ] || [ -n "$REMAINING_VOL" ] || [ -n "$REMAINING_NET" ]; then
        warn "Residual PhobosWG resources still present:"
        [ -n "$REMAINING_CT" ] && printf '    containers: %s\n' $REMAINING_CT
        [ -n "$REMAINING_VOL" ] && printf '    volumes:    %s\n' $REMAINING_VOL
        [ -n "$REMAINING_NET" ] && printf '    networks:   %s\n' $REMAINING_NET
    fi
fi
