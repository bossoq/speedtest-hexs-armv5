# speedtest-hexs-armv5: Ookla speedtest (armel, static) on a busybox arm/v5 base,
# looping every 6h and pushing results to InfluxDB. For the MikroTik hEX S (NK).
# Cross-builds on amd64 (fetch pinned to BUILDPLATFORM, no qemu).
ARG ST_VERSION=1.2.0
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS build
ARG ST_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL -o /tmp/s.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-${ST_VERSION}-linux-armel.tgz" \
 && mkdir -p /out && tar xzf /tmp/s.tgz -C /out speedtest \
 && chmod +x /out/speedtest \
 && rm -rf /var/lib/apt/lists/*

FROM arm32v5/busybox:1.37.0-uclibc
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/speedtest /usr/bin/speedtest
COPY entrypoint.sh /entrypoint.sh
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs
ENTRYPOINT ["/bin/sh","/entrypoint.sh"]
