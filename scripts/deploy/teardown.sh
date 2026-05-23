#!/usr/bin/env bash
set -euo pipefail

# Stop and remove the PhobosWG stack on a remote host.
# With --purge also deletes volumes (sqlite DB, wireguard keys) AND the repo dir.
#
# Usage:
#   scripts/deploy/teardown.sh <user@host> [--path <remote-dir>] [--purge]

REMOTE=""
REMOTE_PATH="/opt/phoboswg"
PURGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --path) REMOTE_PATH="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else echo "Unknown arg: $1" >&2; exit 1; fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || { echo "Usage: $0 <user@host> [--path <dir>] [--purge]" >&2; exit 1; }

if [ $PURGE -eq 1 ]; then
  ssh "$REMOTE" "
    cd $REMOTE_PATH 2>/dev/null && {
      docker compose -f docker-compose.https.yml down -v --remove-orphans 2>/dev/null || true
      docker compose down -v --remove-orphans 2>/dev/null || true
    }
    docker rmi phobos:local ghcr.io/ground-zerro/phobos:latest 2>/dev/null || true
    rm -rf $REMOTE_PATH
  "
  echo "Purged container, volumes, and $REMOTE_PATH."
else
  ssh "$REMOTE" "
    cd $REMOTE_PATH && {
      docker compose -f docker-compose.https.yml down 2>/dev/null || true
      docker compose down 2>/dev/null || true
    }
  "
  echo "Container stopped. Volumes and repo preserved at $REMOTE_PATH."
fi
