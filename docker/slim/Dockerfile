# Dockerfile for Node.js with pointer compression - Slim variant
# Multi-stage build: compile on bookworm, runtime on bookworm-slim

# =============================================================================
# Stage 1: Build Node.js with pointer compression
# =============================================================================
FROM debian:bookworm AS builder

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
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
RUN git clone --depth 1 --branch v25.x https://github.com/nodejs/node.git .

# Configure with pointer compression enabled
# Use prefix to install to a clean directory for easy copying
RUN ./configure \
    --experimental-enable-pointer-compression \
    --prefix=/usr/local

# Build Node.js using all available cores
RUN make -j$(nproc)

# Install to the prefix directory
RUN make install DESTDIR=/node-install

# =============================================================================
# Stage 2: Runtime image with minimal dependencies
# =============================================================================
FROM debian:bookworm-slim

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy Node.js installation from builder
COPY --from=builder /node-install/usr/local /usr/local

# Verify installation
RUN node --version && npm --version

# Set working directory for running applications
WORKDIR /app

# Default command
CMD ["node"]
