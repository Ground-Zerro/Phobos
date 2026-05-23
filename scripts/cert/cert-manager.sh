#!/usr/bin/env bash
#
# PhobosWG certificate manager.
#
# Runs on the host where docker is running. Manages TLS certificates for the
# Caddy sidecar (docker-compose.https.yml). Supports:
#   - Let's Encrypt for a domain (acme.sh + standalone HTTP-01)
#   - Let's Encrypt shortlived for a bare IP (~6 days, auto-renew)
#   - Self-signed certificate for IP/hostname (openssl)
#   - Import existing cert/key files
#   - List / show / delete
#
# Storage layout (under CERT_ROOT, default /opt/phoboswg/certs):
#   <name>/fullchain.pem   full chain (leaf + intermediates)
#   <name>/privkey.pem     private key (mode 0600)
#   <name>/origin          type marker: letsencrypt | letsencrypt-ip | self-signed | imported
#   active -> <name>       symlink to the cert currently used by Caddy
#
# After issuing/switching a cert, the script tells Caddy to reload the
# config (no container restart needed, no dropped connections).
#
# Usage:
#   cert-manager.sh                     # interactive menu
#   cert-manager.sh issue-le <domain>   # non-interactive Let's Encrypt
#   cert-manager.sh issue-le-ip         # non-interactive IP shortlived
#   cert-manager.sh self-signed <host>  # self-signed
#   cert-manager.sh import <name> <cert> <key>
#   cert-manager.sh list
#   cert-manager.sh show
#   cert-manager.sh activate <name>
#   cert-manager.sh delete <name>
#   cert-manager.sh reload              # just reload Caddy with current active

set -euo pipefail

CERT_ROOT="${CERT_ROOT:-/opt/phoboswg/certs}"
CADDY_CONTAINER="${CADDY_CONTAINER:-phobos-caddy}"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

log()  { printf "${blue}[*]${plain} %s\n" "$*"; }
ok()   { printf "${green}[+]${plain} %s\n" "$*"; }
warn() { printf "${yellow}[!]${plain} %s\n" "$*"; }
err()  { printf "${red}[-]${plain} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

is_domain() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_ipv6() {
  [[ "$1" =~ : ]] && [[ "$1" =~ ^[0-9a-fA-F:]+$ ]]
}

port_in_use() {
  local p=$1
  ss -Hltn "sport = :$p" 2>/dev/null | grep -q . \
    || ss -Hlun "sport = :$p" 2>/dev/null | grep -q .
}

detect_public_ip() {
  local ip
  for src in https://api.ipify.org https://4.ident.me https://ifconfig.me; do
    ip=$(curl -s --max-time 3 "$src" || true)
    if is_ipv4 "$ip"; then echo "$ip"; return 0; fi
  done
  return 1
}

ensure_cert_root() {
  mkdir -p "$CERT_ROOT"
  chmod 750 "$CERT_ROOT"
}

install_acme() {
  if command -v ~/.acme.sh/acme.sh &>/dev/null; then return 0; fi
  log "Installing acme.sh"
  curl -s https://get.acme.sh | sh -s -- >/dev/null
  [ -x ~/.acme.sh/acme.sh ] || die "acme.sh installation failed"
  ok "acme.sh installed"
}

install_pkg_once() {
  local bin=$1 pkg=$2
  command -v "$bin" >/dev/null 2>&1 && return 0
  log "Installing $pkg"
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q "$pkg"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$pkg"
  else
    die "Cannot install $pkg: no supported package manager found"
  fi
}

store_cert() {
  local name=$1 cert=$2 key=$3 origin=$4
  local dst="$CERT_ROOT/$name"
  rm -rf "$dst"
  mkdir -p "$dst"
  cp "$cert" "$dst/fullchain.pem"
  cp "$key"  "$dst/privkey.pem"
  echo "$origin" >"$dst/origin"
  chmod 644 "$dst/fullchain.pem"
  chmod 600 "$dst/privkey.pem"
  ok "Stored cert at $dst"
}

activate_cert() {
  local name=$1
  local target="$CERT_ROOT/$name"
  [ -f "$target/fullchain.pem" ] || die "No fullchain.pem in $target"
  [ -f "$target/privkey.pem" ]   || die "No privkey.pem in $target"
  ln -sfn "$name" "$CERT_ROOT/active"
  ok "Active cert -> $name"
  reload_caddy
}

reload_caddy() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CADDY_CONTAINER"; then
    warn "$CADDY_CONTAINER is not running — cert stored but not loaded"
    return 0
  fi
  log "Reloading Caddy"
  if docker exec "$CADDY_CONTAINER" caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    ok "Caddy reloaded"
  else
    warn "caddy reload failed, restarting container"
    docker restart "$CADDY_CONTAINER" >/dev/null
    ok "Caddy restarted"
  fi
}

issue_letsencrypt_domain() {
  local domain=${1:-}
  if [ -z "$domain" ]; then
    read -rp "Domain: " domain
  fi
  is_domain "$domain" || die "Invalid domain: $domain"

  install_pkg_once socat socat
  install_pkg_once curl curl
  install_acme

  local port=${ACME_PORT:-80}
  if port_in_use "$port"; then
    warn "Port $port is busy — stopping Caddy temporarily"
    docker stop "$CADDY_CONTAINER" >/dev/null 2>&1 || true
    local restarted=1
  fi

  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf $tmp" RETURN

  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >/dev/null
  ~/.acme.sh/acme.sh --issue -d "$domain" --standalone --httpport "$port" --force \
    || { [ "${restarted:-0}" = 1 ] && docker start "$CADDY_CONTAINER" >/dev/null; die "acme.sh issue failed"; }
  ~/.acme.sh/acme.sh --installcert -d "$domain" \
    --key-file       "$tmp/privkey.pem" \
    --fullchain-file "$tmp/fullchain.pem" >/dev/null
  ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true

  store_cert "$domain" "$tmp/fullchain.pem" "$tmp/privkey.pem" letsencrypt
  [ "${restarted:-0}" = 1 ] && docker start "$CADDY_CONTAINER" >/dev/null
  activate_cert "$domain"
}

issue_letsencrypt_ip() {
  install_pkg_once socat socat
  install_pkg_once curl curl
  install_acme

  local ip
  ip=$(detect_public_ip) || die "Failed to detect public IPv4"
  log "Server IPv4: $ip"

  local port=${ACME_PORT:-80}
  if port_in_use "$port"; then
    warn "Port $port is busy — stopping Caddy temporarily"
    docker stop "$CADDY_CONTAINER" >/dev/null 2>&1 || true
    local restarted=1
  fi

  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf $tmp" RETURN

  ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >/dev/null
  ~/.acme.sh/acme.sh --issue -d "$ip" \
    --standalone \
    --server letsencrypt \
    --certificate-profile shortlived \
    --days 6 \
    --httpport "$port" --force \
    || { [ "${restarted:-0}" = 1 ] && docker start "$CADDY_CONTAINER" >/dev/null; die "acme.sh issue failed"; }
  ~/.acme.sh/acme.sh --installcert -d "$ip" \
    --key-file       "$tmp/privkey.pem" \
    --fullchain-file "$tmp/fullchain.pem" >/dev/null
  ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true

  store_cert "ip-$ip" "$tmp/fullchain.pem" "$tmp/privkey.pem" letsencrypt-ip
  [ "${restarted:-0}" = 1 ] && docker start "$CADDY_CONTAINER" >/dev/null
  activate_cert "ip-$ip"
}

issue_self_signed() {
  local host=${1:-}
  if [ -z "$host" ]; then
    read -rp "Hostname or IP for cert SAN: " host
  fi
  [ -n "$host" ] || die "Host required"
  install_pkg_once openssl openssl

  local name="self-$host"
  local tmp
  tmp=$(mktemp -d)
  trap "rm -rf $tmp" RETURN

  local san
  if is_ipv4 "$host" || is_ipv6 "$host"; then
    san="IP:$host"
  else
    san="DNS:$host"
  fi

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmp/privkey.pem" \
    -out    "$tmp/fullchain.pem" \
    -days 3650 \
    -subj "/CN=$host" \
    -addext "subjectAltName=$san" >/dev/null 2>&1

  store_cert "$name" "$tmp/fullchain.pem" "$tmp/privkey.pem" self-signed
  activate_cert "$name"
}

import_cert() {
  local name=${1:-} cert=${2:-} key=${3:-}
  if [ -z "$name" ] || [ -z "$cert" ] || [ -z "$key" ]; then
    read -rp "Name (identifier for this cert, e.g. mydomain.com): " name
    read -rp "Path to fullchain PEM: " cert
    read -rp "Path to private key PEM: " key
  fi
  [ -f "$cert" ] || die "Cert file not found: $cert"
  [ -f "$key" ]  || die "Key file not found: $key"

  openssl x509 -in "$cert" -noout -text >/dev/null 2>&1 || die "Not a valid PEM cert: $cert"
  openssl pkey -in "$key"  -noout         >/dev/null 2>&1 || die "Not a valid PEM key: $key"

  store_cert "$name" "$cert" "$key" imported
  activate_cert "$name"
}

list_certs() {
  ensure_cert_root
  local active=""
  [ -L "$CERT_ROOT/active" ] && active=$(readlink "$CERT_ROOT/active")
  printf "%-30s %-16s %-10s %s\n" "NAME" "ORIGIN" "ACTIVE" "EXPIRES"
  printf -- "%s\n" "---------------------------------------------------------------"
  for dir in "$CERT_ROOT"/*/; do
    [ -d "$dir" ] || continue
    local name
    name=$(basename "$dir")
    [ "$name" = "active" ] && continue
    local origin="unknown"
    [ -f "$dir/origin" ] && origin=$(cat "$dir/origin")
    local mark=""
    [ "$name" = "$active" ] && mark="*"
    local exp=""
    if [ -f "$dir/fullchain.pem" ]; then
      exp=$(openssl x509 -in "$dir/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    fi
    printf "%-30s %-16s %-10s %s\n" "$name" "$origin" "$mark" "$exp"
  done
}

show_active() {
  ensure_cert_root
  if [ ! -L "$CERT_ROOT/active" ]; then
    warn "No active certificate"
    return 1
  fi
  local target
  target=$(readlink "$CERT_ROOT/active")
  echo "Active cert:  $target"
  echo "Path:         $CERT_ROOT/$target"
  echo "Origin:       $(cat "$CERT_ROOT/$target/origin" 2>/dev/null || echo unknown)"
  echo "Subject:      $(openssl x509 -in "$CERT_ROOT/$target/fullchain.pem" -noout -subject 2>/dev/null | sed 's/subject=//')"
  echo "Issuer:       $(openssl x509 -in "$CERT_ROOT/$target/fullchain.pem" -noout -issuer  2>/dev/null | sed 's/issuer=//')"
  echo "Valid from:   $(openssl x509 -in "$CERT_ROOT/$target/fullchain.pem" -noout -startdate 2>/dev/null | sed 's/notBefore=//')"
  echo "Valid until:  $(openssl x509 -in "$CERT_ROOT/$target/fullchain.pem" -noout -enddate   2>/dev/null | sed 's/notAfter=//')"
  echo "SAN:          $(openssl x509 -in "$CERT_ROOT/$target/fullchain.pem" -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//')"
}

delete_cert() {
  local name=${1:-}
  [ -n "$name" ] || { read -rp "Cert name to delete: " name; }
  [ -d "$CERT_ROOT/$name" ] || die "Cert $name does not exist"
  local active=""
  [ -L "$CERT_ROOT/active" ] && active=$(readlink "$CERT_ROOT/active")
  [ "$name" = "$active" ] && die "Cannot delete active cert; activate another first"
  rm -rf "$CERT_ROOT/$name"
  ok "Deleted $name"
}

activate_by_name() {
  local name=${1:-}
  [ -n "$name" ] || { read -rp "Cert name to activate: " name; }
  [ -d "$CERT_ROOT/$name" ] || die "Cert $name does not exist"
  activate_cert "$name"
}

menu() {
  ensure_cert_root
  while true; do
    echo
    echo -e "${green}PhobosWG TLS certificate manager${plain} — store: $CERT_ROOT"
    echo -e "  ${green}1${plain}) Let's Encrypt for a domain"
    echo -e "  ${green}2${plain}) Let's Encrypt shortlived for this server's IP (auto-renew ~6 days)"
    echo -e "  ${green}3${plain}) Self-signed certificate (IP or hostname)"
    echo -e "  ${green}4${plain}) Import existing certificate files"
    echo -e "  ${green}5${plain}) List certificates"
    echo -e "  ${green}6${plain}) Show active certificate"
    echo -e "  ${green}7${plain}) Activate a stored certificate"
    echo -e "  ${green}8${plain}) Delete a stored certificate"
    echo -e "  ${green}9${plain}) Reload Caddy with current active cert"
    echo -e "  ${green}0${plain}) Exit"
    read -rp "Choose: " c
    case "$c" in
      1) issue_letsencrypt_domain ;;
      2) issue_letsencrypt_ip ;;
      3) issue_self_signed ;;
      4) import_cert ;;
      5) list_certs ;;
      6) show_active || true ;;
      7) activate_by_name ;;
      8) delete_cert ;;
      9) reload_caddy ;;
      0|q|exit) break ;;
      *) warn "Unknown option" ;;
    esac
  done
}

cmd=${1:-menu}
shift || true
case "$cmd" in
  menu)           menu ;;
  issue-le)       issue_letsencrypt_domain "$@" ;;
  issue-le-ip)    issue_letsencrypt_ip ;;
  self-signed)    issue_self_signed "$@" ;;
  import)         import_cert "$@" ;;
  list)           list_certs ;;
  show)           show_active ;;
  activate)       activate_by_name "$@" ;;
  delete)         delete_cert "$@" ;;
  reload)         reload_caddy ;;
  -h|--help|help)
    sed -n '3,35p' "$0"
    ;;
  *) die "Unknown command: $cmd (use --help)" ;;
esac
