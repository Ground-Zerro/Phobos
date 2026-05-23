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
  scripts/deploy/remote-deploy.sh <user@host> [--port <obfuscator-udp-port>] [--path <remote-dir>] [--https] [--image <tag>] [--platform <platform>] [--multi-arch] [--push]
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
cd "$REPO_ROOT"

COMPOSE_FILE="docker-compose.yml"
[ $HTTPS -eq 1 ] && COMPOSE_FILE="docker-compose.https.yml"

echo "==> Checking SSH connectivity to $REMOTE"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" true

echo "==> Ensuring Docker and rsync are installed on $REMOTE"
ssh "$REMOTE" '
  set -e
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com | sh
  fi
  if ! command -v rsync >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rsync
    elif command -v yum >/dev/null 2>&1; then
      yum install -y -q rsync
    fi
  fi
  systemctl enable --now docker 2>/dev/null || true
'

echo "==> Syncing project tree to $REMOTE:$REMOTE_PATH"
ssh "$REMOTE" "mkdir -p $REMOTE_PATH"
rsync -az --delete \
  --exclude 'node_modules' \
  --exclude '.nuxt' \
  --exclude '.output' \
  --exclude 'data' \
  --exclude '.git' \
  --exclude 'plan' \
  --exclude 'MERGE_PLAN.md' \
  --exclude 'certs' \
  "$REPO_ROOT/" "$REMOTE:$REMOTE_PATH/"

if [ "$PUSH" -eq 1 ]; then
  echo "==> Building and pushing image ($IMAGE_TAG, platforms=$PLATFORMS)"
  docker buildx build --platform "$PLATFORMS" -t "$IMAGE_TAG" --push .
  echo "==> Pulling image on $REMOTE"
  ssh "$REMOTE" "docker pull $IMAGE_TAG"
else
  echo "==> Building image locally ($IMAGE_TAG, platform=$PLATFORMS)"
  docker buildx build --platform "$PLATFORMS" -t "$IMAGE_TAG" --load .
  echo "==> Transferring image to $REMOTE"
  docker save "$IMAGE_TAG" | ssh "$REMOTE" 'docker load'
fi

if [ $HTTPS -eq 1 ]; then
  echo "==> Checking for active TLS certificate"
  has_cert=$(ssh "$REMOTE" "[ -f $REMOTE_PATH/certs/active/fullchain.pem ] && [ -f $REMOTE_PATH/certs/active/privkey.pem ] && echo yes || echo no")
  if [ "$has_cert" != "yes" ]; then
    echo
    echo "    No active TLS certificate found. Launching cert manager..."
    echo "    (1 = Let's Encrypt domain, 2 = Let's Encrypt IP, 3 = Self-signed)"
    echo
    ssh -t "$REMOTE" "CERT_ROOT=$REMOTE_PATH/certs $REMOTE_PATH/scripts/cert/cert-manager.sh"
    has_cert=$(ssh "$REMOTE" "[ -f $REMOTE_PATH/certs/active/fullchain.pem ] && [ -f $REMOTE_PATH/certs/active/privkey.pem ] && echo yes || echo no")
    [ "$has_cert" = "yes" ] || { echo "Cert manager exited without an active cert; aborting." >&2; exit 1; }
  else
    echo "    Active cert present — reusing."
  fi
fi

echo "==> Starting stack (compose=$COMPOSE_FILE, OBF_PORT=$OBF_PORT)"
ssh "$REMOTE" "cd $REMOTE_PATH && OBF_PORT=$OBF_PORT WG_EASY_IMAGE=$IMAGE_TAG docker compose -f $COMPOSE_FILE up -d --force-recreate"

echo "==> Waiting for container to become healthy"
poll_s="${WAIT_HEALTHY_POLL_SEC:-2}"
timeout_s="${WAIT_HEALTHY_TIMEOUT_SEC:-240}"
start_ts=$(date +%s)
i=0
while true; do
  status=$(ssh "$REMOTE" 'docker inspect phobos --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}nohealth{{end}}"' 2>/dev/null || echo "missing")
  now_ts=$(date +%s)
  elapsed=$((now_ts - start_ts))
  case "$status" in
    healthy)
      echo "    healthy after ${elapsed}s"
      break
      ;;
    unhealthy)
      echo "    container reported unhealthy after ${elapsed}s"
      ssh "$REMOTE" 'docker logs --tail 80 phobos'
      exit 1
      ;;
    missing)
      echo "    container missing"
      exit 1
      ;;
    *)
      if [ $((i % 5)) -eq 0 ]; then
        echo "    status=${status} elapsed=${elapsed}s/${timeout_s}s"
      fi
      ;;
  esac
  if [ "$elapsed" -ge "$timeout_s" ]; then
    echo "    timeout after ${timeout_s}s"
    ssh "$REMOTE" 'docker logs --tail 120 phobos'
    exit 1
  fi
  i=$((i + 1))
  sleep "$poll_s"
done

echo "==> Summary"
ssh "$REMOTE" 'docker ps --format "{{.Names}} | {{.Status}} | {{.Ports}}"'

HOST=${REMOTE#*@}
echo
if [ $HTTPS -eq 1 ]; then
  echo "UI:        https://$HOST/  (self-signed cert — browser warning expected on first visit)"
else
  echo "UI:        http://$HOST:51821/"
fi
echo "Obf port:  UDP $HOST:$OBF_PORT"
echo "Remote:    $REMOTE:$REMOTE_PATH"
