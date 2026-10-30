# Ghostty 1.4.0 needs GTK >= 4.18 and libadwaita >= 1.7, so ubuntu:24.04 is too old
FROM ubuntu:26.04 AS builder

WORKDIR /app

ENV GHOSTTY_VERSION=1.4.0
# Must match minimum_zig_version in Ghostty's build.zig.zon
ENV ZIG_VERSION=0.17.0
ENV ZIG_SHA256=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026

RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y ca-certificates libgtk-4-dev libgtk4-layer-shell-dev libadwaita-1-dev libxml2-utils minisign wget xz-utils pkg-config gettext
RUN wget https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz \
 && echo "${ZIG_SHA256}  zig-x86_64-linux-${ZIG_VERSION}.tar.xz" | sha256sum -c - \
 && tar xf zig-x86_64-linux-${ZIG_VERSION}.tar.xz
# Use the release tarball, not a git clone: it carries preprocessed files, so
# the build doesn't need blueprint-compiler >= 0.20 (Ubuntu 26.04 ships 0.19).
# Signing public key is from Ghostty's PACKAGING.md.
RUN wget https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz \
         https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz.minisig \
 && minisign -Vm ghostty-${GHOSTTY_VERSION}.tar.gz -P RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV \
 && mkdir ghostty \
 && tar xf ghostty-${GHOSTTY_VERSION}.tar.gz --strip-components=1 -C ghostty
#ENV GDK_DEBUG="gl-disable-gles ghostty"
RUN cd ghostty/ \
 && ../zig-x86_64-linux-${ZIG_VERSION}/zig build -Doptimize=ReleaseFast -Dversion-string=${GHOSTTY_VERSION}

FROM scratch AS exporter
COPY --from=builder /app/ghostty/zig-out/bin/ghostty .
# Keep share/ next to the binary: Ghostty finds its resources relative to itself
COPY --from=builder /app/ghostty/zig-out/share share
