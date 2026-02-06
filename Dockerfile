# Dockerfile to build Node.js with pointer compression enabled

FROM ubuntu:24.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies with newer g++ for C++20 support
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python3 \
    python3-pip \
    curl \
    ca-certificates \
    g++-12 \
    gcc-12 \
    make \
    ccache \
    libssl-dev \
    software-properties-common \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Clone the Node.js repository
RUN git clone https://github.com/nodejs/node.git .

# Checkout the PR branch
RUN git checkout v25.x

# Configure the build with pointer compression enabled
RUN ./configure --experimental-enable-pointer-compression

# Build Node.js (using limited cores to see errors clearly)
RUN make -j4 V=1 2>&1 | tee /build/build.log || (tail -200 /build/build.log && exit 1)

# Install the built Node.js
RUN make install

# Verify the installation
RUN node --version && npm --version

# Set working directory for running Node.js
WORKDIR /app

# Default command
CMD ["node"]
