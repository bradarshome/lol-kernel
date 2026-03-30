FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta

# Install base dependencies
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    wget \
    python3 \
    python3-pip \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses-dev \
    lz4 \
    liblz4-tool \
    zlib1g-dev \
    zip \
    unzip \
    cpio \
    xz-utils \
    dwarves \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Install repo tool
RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo \
    && chmod a+rx /usr/local/bin/repo

# Install Bazel (for GKI 2.0 builds)
RUN apt-get update && apt-get install -y apt-transport-https curl gnupg \
    && curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list \
    && apt-get update && apt-get install -y bazel \
    && rm -rf /var/lib/apt/lists/*

# Install Clang/LLVM (latest stable)
RUN apt-get update && apt-get install -y \
    clang \
    lld \
    llvm \
    && rm -rf /var/lib/apt/lists/*

# Set up git config (name can be overridden at build time)
ARG PROJECT_NAME=LolKernel
RUN git config --global user.email "builder@lolkernel.local" \
    && git config --global user.name "$PROJECT_NAME Builder"

# Working directory
WORKDIR /build

# Entry point
ENTRYPOINT ["/bin/bash"]
