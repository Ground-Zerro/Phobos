#!/usr/bin/env bash
set -euo pipefail

# One-command multi-arch build and push for PhobosWG image.
#
# Example (GHCR):
#   REGISTRY=ghcr.io \
#   IMAGE_REPO=my-org/phobos \
#   VERSION_TAG=15.3.0-phobos \
#   ./scripts/buildx-push.sh
#
# Example (Docker Hub):
#   REGISTRY=docker.io \
#   IMAGE_REPO=my-user/phobos \
#   VERSION_TAG=15.3.0-phobos \
#   ./scripts/buildx-push.sh

REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_REPO="${IMAGE_REPO:-ground-zerro/phobos}"
VERSION_TAG="${VERSION_TAG:-}"
PUSH_LATEST="${PUSH_LATEST:-true}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER_NAME="${BUILDER_NAME:-phoboswg-multiarch}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
CONTEXT_DIR="${CONTEXT_DIR:-.}"

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_cmd docker

[ -n "$IMAGE_REPO" ] || fail "Set IMAGE_REPO (e.g. ground-zerro/phobos)"
[ -n "$VERSION_TAG" ] || fail "Set VERSION_TAG (e.g. 15.3.0-phobos)"

FULL_IMAGE="${REGISTRY}/${IMAGE_REPO}"
TAG_VERSION="${FULL_IMAGE}:${VERSION_TAG}"
TAG_LATEST="${FULL_IMAGE}:latest"

if ! docker buildx version >/dev/null 2>&1; then
  fail "docker buildx is not available. Install Docker Buildx plugin."
fi

log "Ensuring binfmt emulation is available"
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
ok "binfmt ready"

if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
  log "Creating buildx builder: $BUILDER_NAME"
  docker buildx create --name "$BUILDER_NAME" --driver docker-container --use >/dev/null
else
  log "Using existing buildx builder: $BUILDER_NAME"
  docker buildx use "$BUILDER_NAME"
fi

log "Bootstrapping builder"
docker buildx inspect --bootstrap >/dev/null
ok "Builder ready"

TAGS=(-t "$TAG_VERSION")
if [ "$PUSH_LATEST" = "true" ]; then
  TAGS+=(-t "$TAG_LATEST")
fi

log "Building and pushing multi-arch image"
log "Image: $FULL_IMAGE"
log "Tags:  $VERSION_TAG$( [ "$PUSH_LATEST" = "true" ] && printf ", latest" )"
log "Platforms: $PLATFORMS"

docker buildx build \
  --platform "$PLATFORMS" \
  -f "$DOCKERFILE" \
  "${TAGS[@]}" \
  --push \
  "$CONTEXT_DIR"

ok "Image pushed successfully"
printf '\n'
printf 'Published tags:\n'
printf '  - %s\n' "$TAG_VERSION"
if [ "$PUSH_LATEST" = "true" ]; then
  printf '  - %s\n' "$TAG_LATEST"
fi
printf '\n'
printf 'Pull example:\n'
printf '  docker pull %s\n' "$TAG_VERSION"
