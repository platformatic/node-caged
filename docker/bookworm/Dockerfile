# Dockerfile for Node.js with pointer compression - Debian Bookworm variant
# Full Debian bookworm with glibc, similar to official Node.js images

# Node.js version to build (tag or branch, e.g., v25.6.1 or v25.x)
ARG NODE_VERSION=v25.x

FROM debian:bookworm

# Re-declare ARG after FROM to make it available in this stage
ARG NODE_VERSION

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
# GCC 12 is default in bookworm and supports C++20 required by V8
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-pip \
    curl \
    ca-certificates \
    make \
    ccache \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory for build
WORKDIR /build

# Clone Node.js repository (shallow clone for faster build)
RUN git clone --depth 1 --branch ${NODE_VERSION} https://github.com/nodejs/node.git .

RUN CFLAGS="-march=znver3 -mtune=znver3 -O3" CXXFLAGS="-march=znver3 -mtune=znver3 -O3" \
	./configure --experimental-enable-pointer-compression

# Build Node.js using all available cores
# ccache is available for faster rebuilds if cache is mounted
RUN make -j$(nproc)

# Install Node.js system-wide
RUN make install

# jemalloc - reduce memory fragmentation in long-running Node.js processes
# Note: V8's JS heap uses mmap directly; jemalloc primarily manages Buffer/ArrayBuffer
# backing stores (file I/O chunks), libuv internals, and native addon allocations.
# background_thread: dedicated thread for async decay (avoids inline purge latency)
# dirty_decay_ms:1000 - return dirty pages after 1s (RSS-friendly for containers)
# muzzy_decay_ms:10000 - MADV_FREE muzzy pages after 10s; kernel reclaims under pressure,
#   but longer window avoids re-faulting Buffer pages on high-throughput I/O paths
# narenas:2 - minimize per-arena RSS overhead; acceptable contention at low thread counts
# retain:false - munmap freed extents; keeps VSIZE bounded
RUN apt-get update && apt-get install -y --no-install-recommends libjemalloc2 \
	&& rm -rf /var/lib/apt/lists/*
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
ENV MALLOC_CONF=background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:10000,narenas:2,retain:false


# Cleanup build directory to reduce image size
WORKDIR /
RUN rm -rf /build

# Remove build dependencies to reduce image size
RUN apt-get purge -y \
    build-essential \
    git \
    python3-pip \
    ccache \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify installation
RUN node --version && npm --version

# Set working directory for running applications
WORKDIR /app

# Default command
CMD ["node"]
