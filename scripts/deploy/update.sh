#!/usr/bin/env bash
set -euo pipefail

REMOTE=""
OBF_PORT="51822"
REMOTE_PATH="/opt/phoboswg"
HTTPS=0
IMAGE_TAG="ghcr.io/ground-zerro/phobos:latest"
PLATFORMS="linux/amd64"
PUSH=0

usage() {
  cat <<EOF
Usage:
  scripts/deploy/update.sh <user@host> [--path <remote-dir>] [--port <obfuscator-udp-port>] [--https] [--image <tag>] [--platform <platform>] [--multi-arch] [--push]
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --port) OBF_PORT="$2"; shift 2 ;;
    --path) REMOTE_PATH="$2"; shift 2 ;;
    --https) HTTPS=1; shift ;;
    --image) IMAGE_TAG="$2"; shift 2 ;;
    --platform) PLATFORMS="$2"; shift 2 ;;
    --multi-arch) PLATFORMS="linux/amd64,linux/arm64"; shift ;;
    --push) PUSH=1; shift ;;
    -h|--help) usage ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else echo "Unknown arg: $1" >&2; usage; fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || usage

if [ "$PUSH" -eq 0 ] && [[ "$PLATFORMS" == *","* ]]; then
  echo "Multi-platform build requires --push (registry mode)." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="docker-compose.yml"
[ $HTTPS -eq 1 ] && COMPOSE_FILE="docker-compose.https.yml"

echo "==> Syncing"
rsync -az --delete \
  --exclude 'node_modules' --exclude '.nuxt' --exclude '.output' \
  --exclude 'data' --exclude '.git' --exclude 'plan' --exclude 'MERGE_PLAN.md' \
  --exclude 'certs' \
  "$REPO_ROOT/" "$REMOTE:$REMOTE_PATH/"

if [ "$PUSH" -eq 1 ]; then
  echo "==> Rebuilding and pushing image ($IMAGE_TAG, platforms=$PLATFORMS)"
  docker buildx build --platform "$PLATFORMS" -t "$IMAGE_TAG" --push "$REPO_ROOT"
  echo "==> Pulling image on $REMOTE"
  ssh "$REMOTE" "docker pull $IMAGE_TAG"
else
  echo "==> Rebuilding image ($IMAGE_TAG, platform=$PLATFORMS)"
  docker buildx build --platform "$PLATFORMS" -t "$IMAGE_TAG" --load "$REPO_ROOT"
  echo "==> Transferring image"
  docker save "$IMAGE_TAG" | ssh "$REMOTE" 'docker load'
fi

echo "==> Restarting (compose=$COMPOSE_FILE, volumes preserved)"
ssh "$REMOTE" "cd $REMOTE_PATH && OBF_PORT=$OBF_PORT WG_EASY_IMAGE=$IMAGE_TAG docker compose -f $COMPOSE_FILE up -d --force-recreate"

for i in $(seq 1 60); do
  status=$(ssh "$REMOTE" 'docker inspect phobos --format "{{.State.Health.Status}}"' 2>/dev/null || echo unknown)
  case "$status" in
    healthy) echo "    healthy"; break ;;
    unhealthy) ssh "$REMOTE" 'docker logs --tail 30 phobos'; exit 1 ;;
    *) sleep 5 ;;
  esac
done

ssh "$REMOTE" 'docker ps --format "{{.Names}} | {{.Status}}"'
