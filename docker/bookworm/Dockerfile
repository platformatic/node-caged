# Dockerfile for Node.js with pointer compression - Debian Bookworm variant
# Full Debian bookworm with glibc, similar to official Node.js images

FROM debian:bookworm

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
RUN git clone --depth 1 --branch v25.x https://github.com/nodejs/node.git .

# Configure with pointer compression enabled
RUN ./configure --experimental-enable-pointer-compression

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
    && rm -rf /var/lib/apt/lists/*

# Verify installation
RUN node --version && npm --version

# Set working directory for running applications
WORKDIR /app

# Default command
CMD ["node"]
