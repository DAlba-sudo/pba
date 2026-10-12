# Build context is the repository root:
#
#   docker build -f dev/Dockerfile -t pba-server .
#   docker build -f dev/Dockerfile --build-arg TLS=true -t pba-server:tls .
#
# TLS=true links OpenSSL so the server can use PBA_DATABASE_SSLMODE=require or
# verify-full; the default image contains no OpenSSL.
#
# Stages:
#   zig    - Zig toolchain only
#   build  - fetches dependencies and compiles the server
#   (last) - slim runtime image containing just the server binary
#
# Every stage is cached, so once built, source-only changes rebuild just the
# final `zig build` and copy, without needing network access.

FROM debian:stable-slim AS zig

ARG TARGETARCH
ARG ZIG_VERSION="0.16.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  wget \
  xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      arm64) ZIG_ARCH="aarch64" ;; \
      amd64) ZIG_ARCH="x86_64" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    wget -qO /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" && \
    mkdir -p /opt/zig && \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && \
    rm /tmp/zig.tar.xz && \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /app

CMD ["zig", "version"]

FROM zig AS build

ARG TLS=true

# Debian's libssl-dev installs into the default system paths, which Zig
# searches for native builds, so no -Dopenssl_*_path flags are needed. The
# OpenSSL headers include glibc headers (e.g. sys/types.h), and linking the
# system OpenSSL natively needs glibc's dev files, hence libc6-dev.
RUN if [ "${TLS}" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends libssl-dev libc6-dev && \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Fetch dependencies in their own layer, keyed only on build.zig.zon and the
# vendored path dependency in third_party/ (whose URL dependencies are fetched
# too), so edits to build.zig or the sources reuse the cached dependencies. A
# stub build.zig is all `--fetch` needs; the real one is copied afterwards.
COPY build.zig.zon ./
COPY third_party/ third_party/
RUN echo 'pub fn build(_: *@import("std").Build) void {}' > build.zig && \
    zig build --fetch=all

COPY build.zig ./
COPY cmd/ cmd/
COPY internal/ internal/
COPY html/ html/
RUN zig build -Doptimize=ReleaseSafe -Dtls=${TLS}

FROM debian:stable-slim

ARG TLS=false

# libssl3t64 is the OpenSSL 3 runtime in Debian 13 (trixie).
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  $([ "${TLS}" = "true" ] && echo libssl3t64) \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/zig-out/bin/server /usr/local/bin/server

USER nobody

ENTRYPOINT ["server"]
