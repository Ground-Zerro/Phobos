#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${DEPLOY_DIR:-/opt/phoboswg}"
COMPOSE_FILE="docker-compose.yml"

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m  !\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash $0"

printf '\e[1;31m'
printf '┌─────────────────────────────────────────────┐\n'
printf '│  DESTRUCTIVE OPERATION — NO UNDO POSSIBLE   │\n'
printf '│                                             │\n'
printf '│  Will permanently remove:                   │\n'
printf '│    • PhobosWG container                     │\n'
printf '│    • Docker volumes (wireguard keys, DB)    │\n'
printf '│    • Docker network phobos_wg               │\n'
printf '│    • Docker image ground-zerro/phobos       │\n'
printf '│    • Deploy directory %s         │\n' "$DEPLOY_DIR"
printf '│    • /var/log/phoboswg (if present)         │\n'
printf '└─────────────────────────────────────────────┘\n'
printf '\e[0m'
printf '\nType YES to continue: '
read -r CONFIRM
[ "$CONFIRM" = "YES" ] || { warn "Aborted."; exit 0; }

log "Stopping container"
if [ -d "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/$COMPOSE_FILE" ]; then
    docker compose -f "$DEPLOY_DIR/$COMPOSE_FILE" down \
        --remove-orphans --timeout 15 2>/dev/null || true
    ok "Compose stack torn down"
else
    docker stop phobos 2>/dev/null && docker rm phobos 2>/dev/null || true
    warn "No compose file found — stopped container directly"
fi

log "Removing Docker volumes"
for VOL in phobos_etc_wireguard phobos_sqlite_data phobos_certs_data phobos_acme_data phobos_caddy_data phobos_caddy_config; do
    if docker volume inspect "$VOL" >/dev/null 2>&1; then
        docker volume rm "$VOL"
        ok "Volume removed: $VOL"
    fi
done

log "Removing Docker network"
for NET in phobos_wg phoboswg_wg; do
    if docker network inspect "$NET" >/dev/null 2>&1; then
        docker network rm "$NET"
        ok "Network removed: $NET"
    fi
done

log "Removing Docker images"
for IMG in "ghcr.io/ground-zerro/phobos:latest"; do
    if docker image inspect "$IMG" >/dev/null 2>&1; then
        docker rmi "$IMG"
        ok "Image removed: $IMG"
    fi
done

log "Removing deploy directory: $DEPLOY_DIR"
if [ -d "$DEPLOY_DIR" ]; then
    rm -rf "$DEPLOY_DIR"
    ok "Removed $DEPLOY_DIR"
else
    warn "Deploy directory not found, skipping"
fi

log "Removing logs"
for LOG_PATH in /var/log/phoboswg /var/log/phoboswg.log; do
    if [ -e "$LOG_PATH" ]; then
        rm -rf "$LOG_PATH"
        ok "Removed $LOG_PATH"
    fi
done

for ENV_FILE in /root/.phoboswg.env /etc/phoboswg.env; do
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        ok "Removed $ENV_FILE"
    fi
done

printf '\n\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n'
printf '\e[1;32m  PhobosWG fully removed from this server\e[0m\n'
printf '\e[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m\n\n'
