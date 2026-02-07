# Node.js Pointer Compression Experiments

This repository contains experiments for building Node.js with V8 pointer compression enabled. Pointer compression is a V8 optimization that reduces memory usage by using 32-bit compressed pointers instead of full 64-bit pointers.

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

- **Heap limit**: Pointer compression limits the heap to 4GB (vs ~16GB without)
- **Compatibility**: Requires building Node.js from source with `--experimental-enable-pointer-compression`

## How It Works

The Dockerfile builds Node.js from the v25.x branch with the `--experimental-enable-pointer-compression` configure flag. This enables V8's pointer compression feature which uses 32-bit offsets from a base address instead of full 64-bit pointers.

## Test Scripts

- `tests/verify-pointer-compression.js` - Verifies pointer compression is enabled by checking heap limits
- `tests/memory-benchmark.js` - Benchmarks memory usage with pointer-heavy data structures
