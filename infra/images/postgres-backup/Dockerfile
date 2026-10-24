FROM golang:1.26-alpine AS minio-client

# Official binary downloads and container images are no longer public.
# Build the client from a fixed upstream release instead.
RUN CGO_ENABLED=0 GOBIN=/out go install github.com/minio/mc@RELEASE.2025-08-13T08-35-41Z

FROM postgres:16-alpine

RUN apk add --no-cache ca-certificates
COPY --from=minio-client /out/mc /usr/local/bin/mc

COPY infra/images/postgres-backup/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

USER 70:70

ENTRYPOINT ["/usr/local/bin/backup.sh"]
