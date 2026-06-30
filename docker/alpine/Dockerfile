# Dockerfile for Node.js with pointer compression - Alpine variant
# Uses musl libc instead of glibc - smallest image but experimental
#
# WARNING: This is an experimental build. The combination of musl libc
# and V8 pointer compression is not extensively tested.

# Node.js version to build (tag or branch, e.g., v26.1.0 or v26.x)
ARG NODE_VERSION=v26.x
ARG RUST_VERSION=stable

FROM alpine:3.21 AS builder

# Re-declare ARG after FROM to make it available in this stage
ARG NODE_VERSION
ARG RUST_VERSION

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# Install build dependencies
# Alpine uses musl libc and different package names
RUN apk add --no-cache \
    build-base \
    git \
    python3 \
    curl \
    ca-certificates \
    linux-headers \
    openssl-dev \
    ccache \
    bash \
    procps

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
# Note: Some configure options may differ on Alpine/musl
RUN ./configure \
    --experimental-enable-pointer-compression \
    --v8-enable-temporal-support \
    --prefix=/usr/local

# Build Node.js using all available cores
# V8 may have warnings with musl, so we allow them
RUN make -j$(nproc)

# Install to a clean directory for copying
RUN make install DESTDIR=/node-install

# =============================================================================
# Stage 2: Runtime image
# =============================================================================
FROM alpine:3.21

# Install only runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    libssl3 \
    libstdc++ \
    libgcc

# Copy Node.js installation from builder
COPY --from=builder /node-install/usr/local /usr/local

# Verify installation
RUN node --version && npm --version

# Set working directory for running applications
WORKDIR /app

# Default command
CMD ["node"]
