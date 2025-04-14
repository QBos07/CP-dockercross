# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

FROM --platform=$BUILDPLATFORM debian:stable-slim AS ct-ng-build
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    gcc g++ gperf bison flex texinfo help2man make libncurses-dev \
    python3-dev autoconf automake libtool libtool-bin gawk wget bzip2 xz-utils unzip \
    patch libstdc++6 rsync git meson ninja-build
RUN apt-get install -y --reinstall ca-certificates
RUN mkdir -p /ct-ng-build
WORKDIR /ct-ng-build
RUN git clone https://github.com/QBos07/crosstool-ng.git --branch sh-fpu --depth=1
WORKDIR /ct-ng-build/crosstool-ng
RUN ./bootstrap && ./configure --prefix=/ct-ng
RUN make -j && make -j install

FROM --platform=$BUILDPLATFORM debian:stable-slim AS toolchain-build
COPY --from=xx / /
ENV XX_CC_PREFER_LINKER=ld
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    gperf bison flex texinfo help2man make libncurses6 \
    autoconf automake libtool libtool-bin gawk wget bzip2 xz-utils unzip \
    patch rsync git meson ninja-build \
    gdc gcc g++ binutils libstdc++6 zstd zlib1g-dev
RUN apt-get install -y --reinstall ca-certificates
ARG TARGETPLATFORM
RUN xx-apt-get install -y --no-install-recommends gdc gcc g++ binutils libc6 libstdc++6 zstd zlib1g-dev
COPY --from=ct-ng-build /ct-ng /ct-ng
RUN mkdir -p /toolchain-build
WORKDIR /toolchain-build
COPY defconfig defconfig
RUN (xx-info is-cross && (echo 'CT_CANADIAN=y' >>defconfig || exit 1) || true) && \
    echo "CT_HOST=\"$(xx-info triple)\"" >>defconfig && \
    echo 'CT_PREFIX_DIR="/toolchain"' >>defconfig && \
    echo 'CT_ALLOW_BUILD_AS_ROOT=y' >>defconfig && \
    echo 'CT_ALLOW_BUILD_AS_ROOT_SURE=y' >>defconfig && \
    echo 'CT_LOG_PROGRESS_BAR=n' >>defconfig && \
    cat defconfig && /ct-ng/bin/ct-ng defconfig
RUN /ct-ng/bin/ct-ng source
RUN /ct-ng/bin/ct-ng build || (tail -250 build.log && exit 1) && xx-verify /toolchain/bin/$(/ct-ng/bin/ct-ng show-tuple)-gcc

FROM debian:stable-slim AS final
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    make libncurses6 zstd zlib1g\
    gawk wget bzip2 xz-utils unzip \
    patch libstdc++6 rsync git mold
RUN apt-get install -y --reinstall ca-certificates
COPY --from=toolchain-build /toolchain /toolchain
ENV PATH=$PATH:/toolchain/bin
RUN mkdir -p /work
WORKDIR /work

LABEL org.opencontainers.image.source=https://github.com/QBos07/CP-dockercross
LABEL org.opencontainers.image.authors="qubos@outlook.de"
LABEL org.opencontainers.image.vendor="QBos07"
