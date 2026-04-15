FROM postgres:16-alpine

ARG TARGETOS=linux
ARG TARGETARCH=amd64

RUN apk add --no-cache ca-certificates curl \
    && case "${TARGETARCH}" in \
        amd64) mc_arch="amd64" ;; \
        arm64) mc_arch="arm64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://dl.min.io/client/mc/release/${TARGETOS}-${mc_arch}/mc" -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

COPY infra/images/postgres-backup/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]
