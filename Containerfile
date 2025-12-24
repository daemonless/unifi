ARG BASE_VERSION=15
FROM ghcr.io/daemonless/base:${BASE_VERSION}

ARG FREEBSD_ARCH=amd64
LABEL org.opencontainers.image.title="unifi" \
      org.opencontainers.image.description="UniFi Network Application on FreeBSD" \
      org.opencontainers.image.source="https://github.com/daemonless/unifi" \
      org.opencontainers.image.url="https://ui.com/" \
      org.opencontainers.image.documentation="https://help.ui.com/" \
      org.opencontainers.image.licenses="Proprietary" \
      org.opencontainers.image.vendor="daemonless" \
      org.opencontainers.image.authors="daemonless" \
      io.daemonless.port="8443" \
      io.daemonless.arch="${FREEBSD_ARCH}" \
      org.freebsd.jail.allow.mlock="required"

# Install dependencies (OpenJDK 17, MongoDB 7.0)
# snappyjava provides native FreeBSD snappy library (avoids bundled Linux lib)
RUN pkg update && \
    pkg install -y \
        openjdk17 \
        mongodb70 \
        snappyjava \
        ca_root_nss && \
    pkg clean -ay && \
    rm -rf /var/cache/pkg/* /var/db/pkg/repos/*

# Download and install UniFi from Ubiquiti
RUN mkdir -p /usr/local/share/java/unifi && \
    UNIFI_URL=$(fetch -qo - "https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~unifi-controller&filter=eq~~platform~~unix&filter=eq~~channel~~release" | \
        sed -n 's/.*"href":"\([^"]*\/data\)".*/\1/p' | sed -n '1p') && \
    UNIFI_VERSION=$(fetch -qo - "https://fw-update.ubnt.com/api/firmware-latest?filter=eq~~product~~unifi-controller&filter=eq~~platform~~unix&filter=eq~~channel~~release" | \
        sed -n 's/.*"version":"v\([^+]*\).*/\1/p' | sed -n '1p') && \
    echo "Downloading UniFi ${UNIFI_VERSION}..." && \
    fetch -qo - "${UNIFI_URL}" | tar -xzf - -C /usr/local/share/java/unifi --strip-components=1 && \
    echo "${UNIFI_VERSION}" > /usr/local/share/java/unifi/version.txt && \
    mkdir -p /app && echo "${UNIFI_VERSION}" > /app/version

# Create config directory and configure UniFi to use system MongoDB
RUN mkdir -p /config /var/run/unifi && \
    rm -rf /usr/local/share/java/unifi/data && \
    ln -sf /config /usr/local/share/java/unifi/data && \
    echo "db.mongo.local=false" > /config/system.properties && \
    echo "db.mongo.uri=mongodb://127.0.0.1:27117/ace" >> /config/system.properties && \
    chown -R bsd:bsd /config /var/run/unifi /usr/local/share/java/unifi

# Copy service definition and init scripts
COPY root/ /

# Make scripts executable
RUN chmod +x /etc/services.d/*/run /etc/cont-init.d/* 2>/dev/null || true

# Set up s6 service links for unifi and mongodb

# UniFi ports:
# 8443  - Web UI (HTTPS)
# 8080  - Device inform
# 8843  - Guest portal HTTPS
# 8880  - Guest portal HTTP
# 6789  - Mobile throughput test
# 3478/udp - STUN
# 10001/udp - Device discovery
EXPOSE 8443 8080 8843 8880 6789 3478/udp 10001/udp
VOLUME /config


