# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

FROM scratch AS base-packages
COPY --chmod=+x <<EOF /install-base-packages.sh
#!/bin/sh
set -ex
apt-get update -y
apt-get install -y --no-install-recommends \\
make libncurses6 zstd zlib1g ca-certificates \\
gawk wget bzip2 xz-utils unzip \\
patch libstdc++6 rsync git mold openssh-client
EOF

FROM debian:13-slim AS base

FROM --platform=$BUILDPLATFORM base AS build-base
ARG BUILDARCH BUILDVARIANT
RUN --mount=type=cache,id=apt-${BUILDARCH}-${BUILDVARIANT},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${BUILDARCH}-${BUILDVARIANT},target=/var/lib/apt,sharing=locked \
    --mount=type=bind,from=base-packages,source=/install-base-packages.sh,target=/install-base-packages.sh,rw \
    <<EOF cat >> /install-base-packages.sh && /install-base-packages.sh
apt-get install -y --no-install-recommends \\
gcc g++ gperf bison flex texinfo help2man libncurses-dev \\
python3-dev autoconf automake libtool libtool-bin \\
meson ninja-build
EOF

FROM --platform=$BUILDPLATFORM build-base AS ct-ng-build
WORKDIR /ct-ng-build
ADD --keep-git-dir https://github.com/qbos07/crosstool-ng.git#superh-moar-tuples ./
RUN ./bootstrap && ./configure --prefix=/ct-ng
RUN make -j && make -j install

FROM --platform=$BUILDPLATFORM build-base AS toolchain-build
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts
COPY --from=xx / /
COPY --from=ct-ng-build /ct-ng /ct-ng
WORKDIR /toolchain-build
COPY defconfig defconfig
RUN <<EOF cat >> defconfig
CT_PREFIX_DIR="/toolchain"
CT_ALLOW_BUILD_AS_ROOT=y
CT_ALLOW_BUILD_AS_ROOT_SURE=y
CT_LOG_PROGRESS_BAR=n
CT_LOCAL_TARBALLS_DIR="/tarballs"
EOF
ENV XX_CC_PREFER_LINKER=ld
ARG TARGETPLATFORM
RUN --mount=type=cache,id=apt-${BUILDARCH}-${BUILDVARIANT},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${BUILDARCH}-${BUILDVARIANT},target=/var/lib/apt,sharing=locked \
    xx-apt-get install -y --no-install-recommends gdc gcc g++ binutils libc6 libstdc++6 zstd zlib1g-dev
RUN <<EOF
set -ex
(xx-info is-cross && (echo 'CT_CANADIAN=y' >>defconfig || exit 1) || true)
echo "CT_HOST=\"$(xx-info triple)\"" >>defconfig
cat defconfig && /ct-ng/bin/ct-ng defconfig
EOF
RUN --mount=type=ssh \
    --mount=type=cache,target=/tarballs,sharing=locked \
    --mount=type=bind,source=patches,target=patches \
    /ct-ng/bin/ct-ng build || (tail -250 build.log && exit 1) && \
    xx-verify /toolchain/bin/$(/ct-ng/bin/ct-ng show-tuple)-gcc

FROM base AS final
ARG TARGETARCH TARGETVARIANT
RUN --mount=type=cache,id=apt-${TARGETARCH}-${TARGETVARIANT},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${TARGETARCH}-${TARGETVARIANT},target=/var/lib/apt,sharing=locked \
    --mount=type=bind,from=base-packages,source=/install-base-packages.sh,target=/install-base-packages.sh \
    /install-base-packages.sh
COPY --from=toolchain-build /toolchain /toolchain
ENV PATH=$PATH:/toolchain/bin
WORKDIR /work

LABEL org.opencontainers.image.source=https://github.com/QBos07/CP-dockercross
LABEL org.opencontainers.image.authors="qubos@outlook.de"
LABEL org.opencontainers.image.vendor="QBos07"
