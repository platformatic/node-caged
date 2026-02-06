#!/bin/bash
# Run test scripts inside the pointer-compression-enabled Node.js container

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="node-pointer-compression"

# Check if the image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo "Error: Docker image '$IMAGE_NAME' not found."
    echo "Build it first with: docker build --network=host -t $IMAGE_NAME ."
    exit 1
fi

echo "Running tests with pointer-compression-enabled Node.js..."
echo ""

# Run verification script
echo "=== Running verify-pointer-compression.js ==="
docker run --rm -v "$SCRIPT_DIR/tests:/app" "$IMAGE_NAME" node /app/verify-pointer-compression.js
echo ""

# Run memory benchmark
echo "=== Running memory-benchmark.js ==="
docker run --rm -v "$SCRIPT_DIR/tests:/app" "$IMAGE_NAME" node --expose-gc /app/memory-benchmark.js
