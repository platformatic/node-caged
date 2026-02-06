# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains experiments for building Node.js with V8 pointer compression enabled. Pointer compression is a V8 optimization that reduces memory usage by using 32-bit compressed pointers instead of full 64-bit pointers.

## Build Commands

Build the Docker image with pointer-compression-enabled Node.js:
```bash
docker build --network=host -t node-pointer-compression .
```

Note: `--network=host` is required to avoid DNS resolution issues during the build.

Run the container interactively:
```bash
docker run -it node-pointer-compression
```

Run a specific script:
```bash
docker run -v $(pwd):/app node-pointer-compression node /app/your-script.js
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

The Dockerfile builds Node.js from the v25.x branch with the `--experimental-enable-pointer-compression` configure flag. This enables V8's pointer compression feature which is not enabled by default in Node.js builds.

Key build details:
- Base image: Ubuntu 24.04
- Compiler: GCC 12 (required for C++20 support in V8)
- Node.js branch: v25.x
- Build flag: `--experimental-enable-pointer-compression`
