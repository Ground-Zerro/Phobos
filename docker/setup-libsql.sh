#!/bin/sh
set -eux

TA="${TARGETARCH:-}"
if [ -z "$TA" ]; then
  case "$(uname -m)" in
    x86_64) TA=amd64 ;;
    aarch64|arm64) TA=arm64 ;;
    *)
      printf '%s\n' "Unsupported uname -m: $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

case "$TA" in
  amd64)
    MUSL_PKG=linux-x64-musl
    PREFERRED_GNU=linux-x64-gnu
    ;;
  arm64)
    MUSL_PKG=linux-arm64-musl
    PREFERRED_GNU=linux-arm64-gnu
    ;;
  *)
    printf '%s\n' "Unsupported TARGETARCH/uname mapping: ${TA:-empty}" >&2
    exit 1
    ;;
esac

LIBSQL_ROOT=/app/server/node_modules/@libsql

META=""
for cand in "${LIBSQL_ROOT}/${PREFERRED_GNU}/package.json" "${LIBSQL_ROOT}/${MUSL_PKG}/package.json"; do
  if [ -f "$cand" ]; then
    META=$cand
    break
  fi
done

if [ -z "$META" ]; then
  META="$(
    find "$LIBSQL_ROOT" -maxdepth 4 -type f \( \
      -path '*/linux-*-gnu/package.json' -o -path '*/linux-*-musl/package.json' \
    \) -print 2>/dev/null | head -n1 || true
  )"
fi

if [ -z "$META" ] || [ ! -f "$META" ]; then
  printf '%s\n' "No @libsql linux ABI package.json under $LIBSQL_ROOT" >&2
  ls -la "$LIBSQL_ROOT" 2>&1 || true
  exit 1
fi

LIBSQL_VER="$(node /tmp/read-libsql-version.js "$META")"
MUSL_TGZ_URL="https://registry.npmjs.org/@libsql/${MUSL_PKG}/-/${MUSL_PKG}-${LIBSQL_VER}.tgz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL --connect-timeout 30 --retry 8 --retry-delay 3 --retry-all-errors \
  -o /tmp/libsql-musl.tgz "$MUSL_TGZ_URL"; then
  printf '%s\n' "curl failed: $MUSL_TGZ_URL (LIBSQL_VER=$LIBSQL_VER from $META)" >&2
  exit 1
fi

tar -xz -f /tmp/libsql-musl.tgz -C "$tmp"
rm -f /tmp/libsql-musl.tgz

if [ ! -f "$tmp/package/package.json" ]; then
  printf '%s\n' "Unexpected libsql tarball layout (no package/package.json)" >&2
  ls -laR "$tmp" >&2 || true
  exit 1
fi

mkdir -p "$LIBSQL_ROOT"
rm -rf "$LIBSQL_ROOT/$MUSL_PKG"
mv "$tmp/package" "${LIBSQL_ROOT}/${MUSL_PKG}"

rm -rf "$tmp"
trap - EXIT

test -f "${LIBSQL_ROOT}/${MUSL_PKG}/package.json"
ls -la "$LIBSQL_ROOT"/
