#!/usr/bin/env bash
set -euo pipefail

# Tail container logs from a remote host.
# Usage:  scripts/deploy/logs.sh <user@host> [-f | --tail N]

REMOTE=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) echo "Usage: $0 <user@host> [-f | --tail N]"; exit 0 ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else ARGS+=("$1"); fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || { echo "Usage: $0 <user@host> [-f | --tail N]" >&2; exit 1; }

if [ ${#ARGS[@]} -eq 0 ]; then ARGS=(--tail 100); fi

ssh -t "$REMOTE" "docker logs ${ARGS[*]} phobos"
