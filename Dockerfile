FROM debian:bookworm AS unbound

ENV NAME=unbound
ENV UNBOUND_VERSION=1.24.2
ENV UNBOUND_SHA256=44e7b53e008a6dcaec03032769a212b46ab5c23c105284aa05a4f3af78e59cdb
ENV UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.24.2.tar.gz

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
    cd unbound-1.24.2 && \
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

ENV UNBOUND_VERSION=1.24.2

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
