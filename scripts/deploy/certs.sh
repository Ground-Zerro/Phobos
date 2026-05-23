#!/usr/bin/env bash
set -euo pipefail

# Remote wrapper around scripts/cert/cert-manager.sh.
# Runs the cert manager on the deployed host over SSH, attached to your TTY
# so interactive prompts work.
#
# Usage:
#   scripts/deploy/certs.sh <user@host> [--path <remote-dir>] [<cert-manager args>...]
#
# Examples:
#   scripts/deploy/certs.sh root@host                    # interactive menu
#   scripts/deploy/certs.sh root@host list
#   scripts/deploy/certs.sh root@host issue-le example.com
#   scripts/deploy/certs.sh root@host self-signed 94.232.40.58
#   scripts/deploy/certs.sh root@host import my-cert /path/fullchain.pem /path/privkey.pem

REMOTE=""
REMOTE_PATH="/opt/phoboswg"
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --path) REMOTE_PATH="$2"; shift 2 ;;
    -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
    *)
      if [ -z "$REMOTE" ]; then REMOTE="$1"; else ARGS+=("$1"); fi
      shift
      ;;
  esac
done

[ -n "$REMOTE" ] || { sed -n '3,16p' "$0"; exit 1; }

ssh -t "$REMOTE" "CERT_ROOT=$REMOTE_PATH/certs $REMOTE_PATH/scripts/cert/cert-manager.sh ${ARGS[*]}"
