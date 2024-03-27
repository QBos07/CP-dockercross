# syntax=docker/dockerfile:1
FROM debian:stable-slim AS ct-ng-build
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    gcc g++ gperf bison flex texinfo help2man make libncurses-dev \
    python3-dev autoconf automake libtool libtool-bin gawk wget bzip2 xz-utils unzip \
    patch libstdc++6 rsync git meson ninja-build
RUN apt-get install -y --reinstall ca-certificates
RUN mkdir -p /ct-ng-build
WORKDIR /ct-ng-build
RUN git clone https://github.com/crosstool-ng/crosstool-ng.git --depth=1
WORKDIR /ct-ng-build/crosstool-ng
RUN ./bootstrap && ./configure --prefix=/ct-ng
RUN make -j && make -j install
FROM debian:stable-slim AS toolchain-build
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    gcc g++ gperf bison flex texinfo help2man make libncurses6 \
    python3-dev autoconf automake libtool libtool-bin gawk wget bzip2 xz-utils unzip \
    patch libstdc++6 rsync git meson ninja-build
RUN apt-get install -y --reinstall ca-certificates
COPY --from=ct-ng-build /ct-ng /ct-ng
RUN mkdir -p /toolchain-build
WORKDIR /toolchain-build
COPY defconfig defconfig
RUN /ct-ng/bin/ct-ng defconfig
ENV CT_PREFIX /toolchain
ENV CT_ALLOW_BUILD_AS_ROOT_SURE 1
RUN /ct-ng/bin/ct-ng build
ENV PATH $PATH:/toolchain/bin
FROM debian:stable-slim AS sdk-build
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    make libstdc++6 git
RUN apt-get install -y --reinstall ca-certificates
COPY --from=toolchain-build /toolchain /toolchain
RUN mkdir -p /sdk-build
WORKDIR /sdk-build
RUN git clone -b stdlib_compatibility --single-branch https://github.com/diddyholz/hollyhock-2.git --depth=1
WORKDIR /sdk-build/hollyhock-2/sdk
RUN make -j
RUN mkdir -p /sdk
RUN cp -d libsdk.a sdk.o /sdk && cp -r include /sdk
ENV SDK_DIR /sdk
FROM debian:stable-slim AS final
RUN apt-get update -y && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    make libncurses6\
    gawk wget bzip2 xz-utils unzip \
    patch libstdc++6 rsync git
RUN apt-get install -y --reinstall ca-certificates
COPY --from=toolchain-build /toolchain /toolchain
COPY --from=sdk-build /sdk /sdk
RUN mkdir -p /work
WORKDIR /work
