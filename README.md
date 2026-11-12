# Node.js Pointer Compression Experiments

[![Build and Publish Docker Images](https://github.com/platformatic/node-caged/actions/workflows/build-publish.yml/badge.svg)](https://github.com/platformatic/node-caged/actions/workflows/build-publish.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/platformatic/node-caged)](https://hub.docker.com/r/platformatic/node-caged)

This repository contains experiments for building Node.js with V8 pointer compression enabled. Pointer compression is a V8 optimization that reduces memory usage by using 32-bit compressed pointers instead of full 64-bit pointers.

## Docker Images

Pre-built multi-architecture images (amd64/arm64) are available on DockerHub:

```bash
# Pull the latest image (Debian trixie, recommended)
docker pull platformatic/node-caged:latest

# Or use a specific variant
docker pull platformatic/node-caged:trixie    # Full Debian
docker pull platformatic/node-caged:slim      # Minimal Debian
docker pull platformatic/node-caged:alpine    # Alpine Linux (experimental)

# Pin to a major Node.js version (recommended for most users)
docker pull platformatic/node-caged:26
docker pull platformatic/node-caged:26-slim

# Pin to an exact Node.js version
docker pull platformatic/node-caged:26.1.0
docker pull platformatic/node-caged:26.1.0-slim
```

### Available Tags

Only Node.js 26.x is published. Floating tags (`latest`, `trixie`, `slim`, `alpine`) track the highest published major (currently `26`).

| Tag | Description |
|-----|-------------|
| `latest`, `trixie` | Latest build on Debian trixie for the highest major (recommended) |
| `slim` | Minimal Debian trixie-slim runtime for the highest major |
| `alpine` | Alpine Linux with musl libc for the highest major (experimental) |
| `{major}` | Latest patch of major version on trixie (e.g., `26`) |
| `{major}-{variant}` | Latest patch of major version with variant (e.g., `26-slim`, `26-alpine`) |
| `{version}` | Exact Node.js version on trixie (e.g., `26.1.0`) |
| `{version}-{variant}` | Exact version and variant (e.g., `26.1.0-alpine`) |

### Variant Comparison

| Variant | Base Image | Size | Compatibility |
|---------|-----------|------|---------------|
| `trixie` | debian:trixie | ~250MB | Full glibc, best compatibility |
| `slim` | debian:trixie-slim | ~150MB | Minimal glibc runtime |
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

Addons built on `nan` (or the raw V8 API) are tied to the Node.js ABI. Their prebuilt binaries target stock Node.js and must be rebuilt from source against this runtime. Every image ships a `rebuild-nan-addons` helper that finds these addons in `node_modules` (N-API addons are skipped) and rebuilds them with `node-gyp` using the local Node.js headers. When the npm tarball only ships prebuilds (for example `@datadog/pprof`), it clones the package repository at the matching version tag to get `binding.gyp` and the sources.

The runtime images do not include a compiler, so run it in a build stage:

```dockerfile
FROM platformatic/node-caged:slim AS deps
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ git ca-certificates
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && rebuild-nan-addons

FROM platformatic/node-caged:slim
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
CMD ["node", "index.js"]
```

On Alpine, install the tools with `apk add python3 make g++ git`.

```bash
# Scan ./node_modules (default)
rebuild-nan-addons

# Scan a specific directory
rebuild-nan-addons /path/to/node_modules

# List the addons that would be rebuilt, without building
REBUILD_NAN_ADDONS_DETECT_ONLY=1 rebuild-nan-addons
```

The script exits non-zero if any rebuild fails. It has been tested with `node-expat` (NAN, sources in the tarball) and `@datadog/pprof` (prebuilds only, sources fetched from git).

## How It Works

The Dockerfiles build Node.js from the v26.x branch (overridable via the `NODE_VERSION` build arg) with the `--experimental-enable-pointer-compression` configure flag. This enables V8's pointer compression feature which uses 32-bit offsets from a base address instead of full 64-bit pointers.

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
# Build trixie variant
docker build -f docker/trixie/Dockerfile -t node-pointer-compression:trixie .

# Build slim variant
docker build -f docker/slim/Dockerfile -t node-pointer-compression:slim .

# Build alpine variant
docker build -f docker/alpine/Dockerfile -t node-pointer-compression:alpine .
```

## CI/CD

The GitHub Actions workflow builds and publishes multi-architecture images:

- **Trigger**: Manual only (`workflow_dispatch`)
- **Major selection**: Choose `26` or `all` (default) when dispatching; only 26.x is currently built
- **Version detection**: Automatically detects the latest release for each selected major
- **Duplicate check**: Skips a major if its current version already exists on DockerHub
- **Force rebuild**: Option to bypass the version check and rebuild

Images are built natively on both amd64 and arm64 runners for optimal build performance.
