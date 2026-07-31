#!/usr/bin/env bash
set -euo pipefail

ICON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

render_scalable() {
    local source="$1" size="$2"
    rsvg-convert -w "$size" -h "$size" "$source" -o "$STAGING/$size.png"
}

render_raster() {
    local source="$1" size="$2"
    convert "$source" -resize "${size}x${size}" -filter Lanczos "$STAGING/$size.png"
}

compose() {
    local output="$1"
    shift
    local files=()
    local size
    for size in "$@"; do files+=("$STAGING/$size.png"); done
    convert "${files[@]}" -compress zip "$output"
    echo "$(basename "$output"): $*"
}

for size in 256 192 128 96; do render_scalable "$ICON_DIR/phobos.svg" "$size"; done
for size in 64 48 40 32 24 20 16; do render_raster "$ICON_DIR/phobos-small.png" "$size"; done
compose "$ICON_DIR/phobos.ico" 256 192 128 96 64 48 40 32 24 20 16

for size in 256 192 128 96 64 48 40 32 24 20 16; do render_scalable "$ICON_DIR/dot.svg" "$size"; done
compose "$ICON_DIR/dot.ico" 256 192 128 96 64 48 40 32 24 20 16
