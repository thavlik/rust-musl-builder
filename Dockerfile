# Forked from ekidd/rust-musl-builder
# Use Ubuntu 18.04 LTS as our base image.
FROM ubuntu:18.04

# The Rust toolchain to use when building our image.
ARG TOOLCHAIN=stable

# The OpenSSL version to use. We parameterize this because many Rust
# projects will fail to build with 1.1.
ARG OPENSSL_VERSION=1.0.2r
# Necessary because openssl download links are now broken
ARG OPENSSL_SOURCE=https://ftp.openssl.org/source/old/1.0.2/openssl-1.0.2r.tar.gz

# Make sure we have basic dev tools for building C libraries.  Our goal
# here is to support the musl-libc builds and Cargo builds needed for a
# large selection of the most popular crates.
#
# We also set up a `rust` user by default, in whose account we'll install
# the Rust toolchain.  This user has sudo privileges if you need to install
# any more software.
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        curl \
        git \
        musl-dev \
        musl-tools \
        libssl-dev \
        linux-libc-dev \
        pkgconf \
        xutils-dev \
        && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    useradd rust --user-group --create-home --shell /bin/bash

# Static linking for C++ code
RUN ln -s "/usr/bin/g++" "/usr/bin/musl-g++"

# Build a static library version of OpenSSL using musl-libc.  This is needed by
# the popular Rust `hyper` crate.
#
# We point /usr/local/musl/include/linux at some Linux kernel headers (not
# necessarily the right ones) in an effort to compile OpenSSL 1.1's "engine"
# component. It's possible that this will cause bizarre and terrible things to
# happen. There may be "sanitized" header
RUN echo "Building OpenSSL" && \
    ls /usr/include/linux && \
    mkdir -p /usr/local/musl/include && \
    ln -s /usr/include/linux /usr/local/musl/include/linux && \
    ln -s /usr/include/x86_64-linux-gnu/asm /usr/local/musl/include/asm && \
    ln -s /usr/include/asm-generic /usr/local/musl/include/asm-generic && \
    cd /tmp && \
    curl -vLO $OPENSSL_SOURCE && \
    tar xvzf "openssl-$OPENSSL_VERSION.tar.gz" && cd "openssl-$OPENSSL_VERSION" && \
    env CC=musl-gcc ./Configure no-shared no-zlib -fPIC --prefix=/usr/local/musl -DOPENSSL_NO_SECURE_MEMORY linux-x86_64 && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make depend && \
    env C_INCLUDE_PATH=/usr/local/musl/include/ make && \
    make install && \
    rm /usr/local/musl/include/linux /usr/local/musl/include/asm /usr/local/musl/include/asm-generic && \
    rm -r /tmp/*


# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.
USER rust
ENV PATH="/home/rust/.cargo/bin:${PATH}"
ENV CARGO_HOME="/home/rust/.cargo"
ENV RUSTUP_HOME="/home/rust/.rustup"
ENV OPENSSL_DIR=/usr/local/musl/
ENV OPENSSL_INCLUDE_DIR=/usr/local/musl/include/
ENV DEP_OPENSSL_INCLUDE=/usr/local/musl/include/
ENV OPENSSL_LIB_DIR=/usr/local/musl/lib/
ENV OPENSSL_STATIC=1
ENV PKG_CONFIG_ALLOW_CROSS=true
ENV PKG_CONFIG_ALL_STATIC=true
ENV TARGET=musl
RUN mkdir -p ${CARGO_HOME} \
    && curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain $TOOLCHAIN \
    && rustup target add x86_64-unknown-linux-musl \
    && chown -R rust: /home/rust
# (Please feel free to submit pull requests for musl-libc builds of other C
# libraries needed by the most popular and common Rust crates, to avoid
# everybody needing to build them manually.)

# Install some useful Rust tools from source. This will use the static linking
# toolchain, but that should be OK.
#
# We include cargo-audit for compatibility with earlier versions of this image,
# but cargo-deny provides a super-set of cargo-audit's features.
RUN rm -rf /home/rust/.cargo/registry/


# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
ENV PATH=/home/rust/.cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Expect our source code to live in /home/rust/src.  We'll run the build as
# user `rust`, which will be uid 1000, gid 1000 outside the container.
WORKDIR /home/rust/src