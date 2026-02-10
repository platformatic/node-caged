# Node.js with Pointer Compression (node-caged)

Node.js built with V8 pointer compression enabled, delivering **~50% memory reduction** for pointer-heavy data structures.

## Quick Start

```bash
docker pull platformatic/node-caged:latest
docker run -it platformatic/node-caged node
```

## Available Tags

| Tag | Description |
|-----|-------------|
| `latest`, `bookworm` | Debian bookworm (recommended) |
| `slim` | Minimal Debian bookworm-slim |
| `alpine` | Alpine Linux with musl (smallest) |
| `25`, `25-slim`, `25-alpine` | Latest Node.js 25.x |
| `25.6.0`, `25.6.0-slim`, `25.6.0-alpine` | Pinned version |

## Memory Savings

| Data Structure | Standard Node.js | Pointer Compressed | Savings |
|----------------|------------------|-------------------|---------|
| Array of Objects (1M) | 40.47 MB | 20.24 MB | **50%** |
| Nested Objects (500K) | 50.21 MB | 24.64 MB | **51%** |
| Linked List (500K) | 19.08 MB | 9.54 MB | **50%** |

## Tradeoffs

- **Heap limit**: 4GB per isolate (main thread + each worker has its own 4GB limit)
- **Best for**: Memory-constrained environments, high-density deployments

> **Note**: The 4GB limit applies per V8 isolate. Using worker threads, you can exceed 4GB total memory (e.g., 4 workers = 20GB theoretical max).

## Architectures

Multi-arch images for `linux/amd64` and `linux/arm64`.

## Links

- [GitHub Repository](https://github.com/platformatic/node-caged)
- [Platformatic](https://platformatic.dev)
