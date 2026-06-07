# single source of truth for version bumps — edit these two values only.
# the SHA256 is published alongside the tarball at
# https://nlnetlabs.nl/downloads/unbound/unbound-<version>.tar.gz.sha256
ARG UNBOUND_VERSION=1.25.1
ARG UNBOUND_SHA256=0fe8b6277b0959cfd17562debac0aa5f71e0b02dc4ffa9c60271c583edab586f

FROM debian:bookworm AS unbound

# re-declare to pull the global ARGs into this stage's scope
ARG UNBOUND_VERSION
ARG UNBOUND_SHA256
ENV NAME=unbound
ENV UNBOUND_VERSION=${UNBOUND_VERSION}
ENV UNBOUND_SHA256=${UNBOUND_SHA256}
ENV UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz

WORKDIR /tmp/src

RUN build_deps="curl gcc libc-dev libevent-dev libexpat1-dev libnghttp2-dev libssl-dev make" && \
    set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      $build_deps \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      bison \
      flex \
      build-essential \
      libssl-dev \
      libevent-2.1-7 \
      libexpat1 && \
    curl -sSL $UNBOUND_DOWNLOAD_URL -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256} *unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz && \
    rm -f unbound.tar.gz && \
    cd unbound-${UNBOUND_VERSION} && \
    groupadd _unbound && \
    useradd -g _unbound -s /etc -d /dev/null _unbound && \
    ./configure \
        --disable-dependency-tracking \
        --prefix=/opt/unbound \
        --with-pthreads \
        --with-username=_unbound \
        --with-libevent \
        --with-libnghttp2 \
        --enable-tfo-server \
        --enable-tfo-client \
        --enable-event-api && \
    make install && \
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

# build the target image
FROM debian:bookworm

# re-declare to pull the global ARG into this stage's scope
ARG UNBOUND_VERSION

WORKDIR /tmp/src

COPY --from=unbound /opt /opt

RUN set -x && \
    DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends \
      bsdmainutils \
      ca-certificates \
      ldnsutils \
      libevent-2.1-7 \
      libnghttp2-14 \
      libssl3 \
      libexpat1 && \
    groupadd _unbound && \
    useradd -g _unbound -s /etc -d /dev/null _unbound && \
    apt-get purge -y --auto-remove \
      $build_deps && \
    rm -rf \
        /opt/unbound/share/man \
        /tmp/* \
        /var/tmp/* \
        /var/lib/apt/lists/*

COPY data/ /

RUN chmod +x /unbound.sh
RUN chmod +x /test.sh

WORKDIR /opt/unbound/

ENV PATH="/opt/unbound/sbin:$PATH"

ENV UNBOUND_VERSION=${UNBOUND_VERSION}

LABEL org.opencontainers.image.version=${UNBOUND_VERSION} \
      org.opencontainers.image.title="sulrich/docker-unbound" \
      org.opencontainers.image.description="a validating, recursive, and caching DNS resolver" \
      org.opencontainers.image.url="https://github.com/sulrich/docker-unbound" \
      org.opencontainers.image.vendor="steve ulrich" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/sulrich/docker-unbound"

EXPOSE 53/tcp
EXPOSE 53/udp

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD drill @127.0.0.1 cloudflare.com || exit 1

CMD ["/unbound.sh"]
