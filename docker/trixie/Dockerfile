# Dockerfile for Node.js with pointer compression - Debian Trixie variant
# Full Debian trixie with glibc, similar to official Node.js images.
# Trixie ships gcc-14 by default, which is required to build Node.js v26
# (V8's builtins-iterator-inl.h static_assert fails under gcc-12).

# Node.js version to build (tag or branch, e.g., v26.1.0 or v26.x)
ARG NODE_VERSION=v26.x
ARG RUST_VERSION=stable

FROM debian:trixie

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
RUN ./configure \
    --experimental-enable-pointer-compression \
    --v8-enable-temporal-support

# Build Node.js using all available cores
# ccache is available for faster rebuilds if cache is mounted
RUN make -j$(nproc)

# Install Node.js system-wide
RUN make install

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
    && rm -rf /var/lib/apt/lists/* /usr/local/rustup /usr/local/cargo

# Verify installation
RUN node --version && npm --version

# Set working directory for running applications
WORKDIR /app

# Default command
CMD ["node"]
