# Node.js Pointer Compression Experiments

[![Build and Publish Docker Images](https://github.com/platformatic/node-caged/actions/workflows/build-publish.yml/badge.svg)](https://github.com/platformatic/node-caged/actions/workflows/build-publish.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/platformatic/node-caged)](https://hub.docker.com/r/platformatic/node-caged)

This repository contains experiments for building Node.js with V8 pointer compression enabled. Pointer compression is a V8 optimization that reduces memory usage by using 32-bit compressed pointers instead of full 64-bit pointers.

## Docker Images

Pre-built multi-architecture images (amd64/arm64) are available on DockerHub:

```bash
# Pull the latest image (Debian bookworm, recommended)
docker pull platformatic/node-caged:latest

# Or use a specific variant
docker pull platformatic/node-caged:bookworm  # Full Debian
docker pull platformatic/node-caged:slim      # Minimal Debian
docker pull platformatic/node-caged:alpine    # Alpine Linux (experimental)

# Pin to a major Node.js version (recommended for most users)
docker pull platformatic/node-caged:25
docker pull platformatic/node-caged:25-slim
docker pull platformatic/node-caged:25-alpine

# Pin to an exact Node.js version
docker pull platformatic/node-caged:25.6.1
docker pull platformatic/node-caged:25.6.1-slim
```

### Available Tags

| Tag | Description |
|-----|-------------|
| `latest`, `bookworm` | Latest build on Debian bookworm (recommended) |
| `slim` | Minimal Debian bookworm-slim runtime (~100MB smaller) |
| `alpine` | Alpine Linux with musl libc (smallest, experimental) |
| `{major}` | Latest patch of major version on bookworm (e.g., `25`) |
| `{major}-{variant}` | Latest patch of major version with variant (e.g., `25-slim`) |
| `{version}` | Exact Node.js version on bookworm (e.g., `25.6.1`) |
| `{version}-{variant}` | Exact version and variant (e.g., `25.6.1-alpine`) |

### Variant Comparison

| Variant | Base Image | Size | Compatibility |
|---------|-----------|------|---------------|
| `bookworm` | debian:bookworm | ~250MB | Full glibc, best compatibility |
| `slim` | debian:bookworm-slim | ~150MB | Minimal glibc runtime |
| `alpine` | alpine:3.21 | ~100MB | musl libc, experimental |

## Quick Start

Build the Docker image:
```bash
docker build --network=host -t node-pointer-compression .
```

Run the tests:
```bash
./run-tests.sh
```

## Benchmark Results

Memory comparison between standard Node.js 22 and pointer-compressed Node.js 25 (with `--expose-gc`):

| Data Structure | Standard Node 22 | Pointer Compressed | Savings |
|----------------|------------------|-------------------|---------|
| **Array of Objects** (1M items) | 40.47 MB (42.43 B/item) | 20.24 MB (21.22 B/item) | **50%** |
| **Nested Objects** (500K items) | 50.21 MB (105.29 B/item) | 24.64 MB (51.68 B/item) | **51%** |
| **Linked List** (500K items) | 19.08 MB (40.01 B/item) | 9.54 MB (20.01 B/item) | **50%** |
| **Array of Arrays** (500K items) | 38.76 MB (81.28 B/item) | 19.38 MB (40.64 B/item) | **50%** |

### Key Findings

- Pointer compression delivers consistent **~50% memory reduction** across all pointer-heavy data structures
- Bytes-per-item is almost exactly halved, matching the theoretical expectation (32-bit vs 64-bit pointers)
- Baseline memory usage is also lower (2.11 MB vs 3.74 MB)

### Tradeoffs

- **Heap limit**: 4GB per V8 isolate. Each worker thread has its own 4GB limit, so you can exceed 4GB total using multiple workers (e.g., main + 4 workers = 20GB max)
- **Compatibility**: Requires building Node.js from source with `--experimental-enable-pointer-compression`

### Native Addon Compatibility

**N-API addons work correctly** with pointer compression. Tested and verified:

| Addon | Type | Status |
|-------|------|--------|
| `bcrypt` | N-API | ✓ Works |
| `sharp` | N-API | ✓ Works |
| `@napi-rs/uuid` | Rust N-API | ✓ Works |
| `@node-rs/argon2` | Rust N-API | ✓ Works |

**Non-N-API native addons may crash.** Addons using the older V8 native addon API (like `better-sqlite3`) are not compatible with pointer compression and can segfault. Packages that rely on `nan` are especially affected. Always prefer N-API-based alternatives.

### Workarounds for Non-N-API Addons

If your dependency uses `nan` and does not provide binaries built for this runtime, you must force a local rebuild of its native addon.

If the package in `node_modules` still contains source files, try a normal rebuild:

```bash
cd node_modules/<package-name>
pnpm install --ignore-scripts
pnpm run rebuild
s```

Some packages on npm do not ship source files needed to rebuild. In these cases, you may need to fetch the source from the git repository, copy it back into `node_modules`, and run a manual rebuild.

#### Known affected package example

##### `@datadog/pprof`

```bash
cd node_modules/@datadog/pprof
pnpm install --ignore-scripts
PPROF_VERSION=$(node -p "require('./package.json').version")
PPROF_REPO=$(node -p "require('./package.json').repository.url.replace('git+', '')")
git clone -q --depth=1 --branch=v$PPROF_VERSION $PPROF_REPO /tmp/pprof-nodejs > /dev/null 2>&1
mv /tmp/pprof-nodejs/{binding.gyp,bindings} .
rm -rf /tmp/pprof-nodejs
pnpm run rebuild
cd ../../..
```

## How It Works

The Dockerfile builds Node.js from the v25.x branch with the `--experimental-enable-pointer-compression` configure flag. This enables V8's pointer compression feature which uses 32-bit offsets from a base address instead of full 64-bit pointers.

## Test Scripts

- `tests/verify-pointer-compression.js` - Verifies pointer compression is enabled by checking heap limits
- `tests/memory-benchmark.js` - Benchmarks memory usage with pointer-heavy data structures
- `tests/worker-heap-limits.js` - Verifies each worker thread has its own 4GB heap limit
- `tests/napi-addon-test.js` - Tests N-API native addon compatibility (requires npm install)

## Building Locally

For local development, use the root Dockerfile:

```bash
# Build for local architecture
docker build --network=host -t node-pointer-compression .

# Run interactively
docker run -it node-pointer-compression

# Run a script
docker run -v $(pwd):/app node-pointer-compression node /app/your-script.js
```

To build a specific variant locally:

```bash
# Build bookworm variant
docker build -f docker/bookworm/Dockerfile -t node-pointer-compression:bookworm .

# Build slim variant
docker build -f docker/slim/Dockerfile -t node-pointer-compression:slim .

# Build alpine variant
docker build -f docker/alpine/Dockerfile -t node-pointer-compression:alpine .
```

## CI/CD

The GitHub Actions workflow builds and publishes multi-architecture images:

- **Trigger**: Manual only (`workflow_dispatch`)
- **Version detection**: Automatically detects latest Node.js v25.x release
- **Duplicate check**: Skips build if version already exists on DockerHub
- **Force rebuild**: Option to bypass version check and rebuild

Images are built natively on both amd64 and arm64 runners for optimal build performance.
