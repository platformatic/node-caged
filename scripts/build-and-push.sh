#!/usr/bin/env bash
#
# Build and push all Docker variants to DockerHub with proper version tags.
# Supports multi-architecture builds (amd64/arm64) using docker buildx.
#
# Usage:
#   ./scripts/build-and-push.sh              # Build and push all variants
#   ./scripts/build-and-push.sh --no-push    # Build only, don't push
#   ./scripts/build-and-push.sh bookworm     # Build and push specific variant
#   ./scripts/build-and-push.sh --local      # Build for local arch only (faster)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-platformatic/node-pointer-compression}"
VARIANTS=("bookworm" "slim" "alpine")
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Parse arguments
PUSH=true
LOCAL_ONLY=false
SELECTED_VARIANTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-push)
            PUSH=false
            shift
            ;;
        --local)
            LOCAL_ONLY=true
            PLATFORMS="linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [VARIANTS...]"
            echo ""
            echo "Options:"
            echo "  --no-push    Build images but don't push to registry"
            echo "  --local      Build for local architecture only (faster)"
            echo "  --help       Show this help message"
            echo ""
            echo "Variants: bookworm, slim, alpine (default: all)"
            echo ""
            echo "Environment variables:"
            echo "  IMAGE_NAME   Docker image name (default: platformatic/node-pointer-compression)"
            echo "  PLATFORMS    Target platforms (default: linux/amd64,linux/arm64)"
            exit 0
            ;;
        *)
            SELECTED_VARIANTS+=("$1")
            shift
            ;;
    esac
done

# Use all variants if none specified
if [[ ${#SELECTED_VARIANTS[@]} -eq 0 ]]; then
    SELECTED_VARIANTS=("${VARIANTS[@]}")
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure buildx is available and configured
setup_buildx() {
    log_info "Setting up docker buildx..."

    if ! docker buildx inspect multiarch-builder &>/dev/null; then
        docker buildx create --name multiarch-builder --use
    else
        docker buildx use multiarch-builder
    fi

    # Bootstrap the builder
    docker buildx inspect --bootstrap
}

# Extract Node.js version from a built image
get_node_version() {
    local image="$1"
    docker run --rm "$image" node --version | sed 's/^v//'
}

# Build a single variant
build_variant() {
    local variant="$1"
    local dockerfile="$PROJECT_DIR/docker/$variant/Dockerfile"

    if [[ ! -f "$dockerfile" ]]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi

    log_info "Building $variant variant for platforms: $PLATFORMS"

    local build_args=(
        --file "$dockerfile"
        --platform "$PLATFORMS"
    )

    if [[ "$PUSH" == "true" ]]; then
        build_args+=(--push)
    elif [[ "$LOCAL_ONLY" == "true" ]]; then
        build_args+=(--load)
    else
        # Multi-arch without push requires --push or outputting to a file
        log_warn "Multi-arch builds require --push or --local. Using --local for this build."
        PLATFORMS="linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')"
        build_args=(--file "$dockerfile" --platform "$PLATFORMS" --load)
    fi

    # First build with a temporary tag to extract version
    local temp_tag="$IMAGE_NAME:${variant}-temp"

    if [[ "$LOCAL_ONLY" == "true" ]] || [[ "$PUSH" == "false" ]]; then
        # For local builds, we can load and inspect
        docker buildx build "${build_args[@]}" --tag "$temp_tag" "$PROJECT_DIR"

        # Extract version
        NODE_VERSION=$(get_node_version "$temp_tag")
        log_info "Detected Node.js version: $NODE_VERSION"

        # Remove temp tag
        docker rmi "$temp_tag" 2>/dev/null || true
    else
        # For push builds, build once and tag appropriately
        # We need to build a local image first to get the version
        log_info "Building local image to detect Node.js version..."
        local local_platform="linux/$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')"
        docker buildx build --file "$dockerfile" --platform "$local_platform" --load --tag "$temp_tag" "$PROJECT_DIR"

        NODE_VERSION=$(get_node_version "$temp_tag")
        log_info "Detected Node.js version: $NODE_VERSION"

        docker rmi "$temp_tag" 2>/dev/null || true
    fi

    # Build tags
    local tags=(
        "--tag" "$IMAGE_NAME:${NODE_VERSION}-${variant}"
        "--tag" "$IMAGE_NAME:${variant}"
    )

    # Bookworm is the default variant
    if [[ "$variant" == "bookworm" ]]; then
        tags+=(
            "--tag" "$IMAGE_NAME:${NODE_VERSION}"
            "--tag" "$IMAGE_NAME:latest"
        )
    fi

    # Final build with all tags
    log_info "Building and tagging $variant..."
    docker buildx build "${build_args[@]}" "${tags[@]}" "$PROJECT_DIR"

    log_success "Built $variant variant"
    echo "  Tags:"
    echo "    - $IMAGE_NAME:${NODE_VERSION}-${variant}"
    echo "    - $IMAGE_NAME:${variant}"
    if [[ "$variant" == "bookworm" ]]; then
        echo "    - $IMAGE_NAME:${NODE_VERSION}"
        echo "    - $IMAGE_NAME:latest"
    fi
}

# Main
main() {
    log_info "Docker image: $IMAGE_NAME"
    log_info "Platforms: $PLATFORMS"
    log_info "Variants: ${SELECTED_VARIANTS[*]}"
    log_info "Push: $PUSH"
    echo ""

    # Check Docker login if pushing
    if [[ "$PUSH" == "true" ]]; then
        if ! docker info 2>/dev/null | grep -q "Username"; then
            log_warn "Not logged in to Docker Hub. Run 'docker login' first."
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    setup_buildx
    echo ""

    # Build each variant
    for variant in "${SELECTED_VARIANTS[@]}"; do
        if [[ ! " ${VARIANTS[*]} " =~ " ${variant} " ]]; then
            log_error "Unknown variant: $variant (valid: ${VARIANTS[*]})"
            exit 1
        fi

        build_variant "$variant"
        echo ""
    done

    log_success "All builds completed!"

    if [[ "$PUSH" == "true" ]]; then
        log_info "Images pushed to Docker Hub: https://hub.docker.com/r/$IMAGE_NAME"
    fi
}

main
