# Dockerfile for Node.js with pointer compression - Slim variant
# Multi-stage build: compile on trixie, runtime on trixie-slim.
# Trixie ships gcc-14 by default (required for Node.js v26 V8).

# Node.js version to build (tag or branch, e.g., v26.1.0 or v26.x)
ARG NODE_VERSION=v26.x
ARG RUST_VERSION=stable

# =============================================================================
# Stage 1: Build Node.js with pointer compression
# =============================================================================
FROM debian:trixie AS builder

# Re-declare ARG after FROM to make it available in this stage
ARG NODE_VERSION
ARG RUST_VERSION

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

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

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y \
        --no-modify-path \
        --profile minimal \
        --default-toolchain "${RUST_VERSION}" \
    && rustc --version \
    && cargo --version

# Set working directory for build
WORKDIR /build

# Clone Node.js repository (shallow clone for faster build)
RUN git clone --depth 1 --branch ${NODE_VERSION} https://github.com/nodejs/node.git .

# Configure with pointer compression enabled
# Use prefix to install to a clean directory for easy copying
RUN ./configure \
    --experimental-enable-pointer-compression \
    --v8-enable-temporal-support \
    --prefix=/usr/local

# Build Node.js using all available cores
RUN make -j$(nproc)

# Install to the prefix directory
RUN make install DESTDIR=/node-install

# =============================================================================
# Stage 2: Runtime image with minimal dependencies
# =============================================================================
FROM debian:trixie-slim

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
