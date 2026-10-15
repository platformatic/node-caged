# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains experiments for building Node.js with V8 pointer compression enabled. Pointer compression is a V8 optimization that reduces memory usage by using 32-bit compressed pointers instead of full 64-bit pointers.

## Build Commands

Build a Docker image variant (trixie, slim, or alpine):
```bash
docker build --network=host -f docker/trixie/Dockerfile -t node-caged .
```

Note: `--network=host` is required to avoid DNS resolution issues during the build.

Run the container interactively:
```bash
docker run -it node-caged
```

Run a specific script:
```bash
docker run -v $(pwd):/app node-caged node /app/your-script.js
```

## Testing

Run all tests:
```bash
./run-tests.sh
```

Test scripts in `tests/`:
- `verify-pointer-compression.js` - Verifies pointer compression is enabled by checking heap limits
- `memory-benchmark.js` - Benchmarks memory usage with pointer-heavy data structures

## Architecture

Dockerfiles in `docker/` build Node.js with the `--experimental-enable-pointer-compression` configure flag. Three variants are available:
- `docker/trixie/Dockerfile` - Full Debian trixie (default)
- `docker/slim/Dockerfile` - Minimal Debian trixie
- `docker/alpine/Dockerfile` - Alpine Linux

Key build details:
- Compiler: GCC 14 (ships with Debian trixie and Alpine 3.21; required because Node.js v26 V8 fails to compile under gcc-12).
- Node.js branch built in CI: v26.x only (v25.x support was dropped). The `node_major` workflow input is kept so a new major can be added by extending its `options` and the `MAJORS` array. Local Dockerfile default is `v26.x`, override with `--build-arg NODE_VERSION=v26.1.0` to pin a tag.
- Build flags: `--experimental-enable-pointer-compression --v8-enable-temporal-support` (Temporal needs the Rust toolchain, installed unconditionally in every Dockerfile).
- Floating Docker tags (`latest`, `trixie`, `slim`, `alpine`) track the highest major; the `LATEST_MAJOR` env var in `.github/workflows/build-publish.yml` controls this.
