# Security Exposure Review

This deployment keeps the public surface intentionally small for the single-user launch.

## Exposure Matrix

### Public

- `https://api.nexavend.store:8443`
  - authenticated API routes under `/v1/...`
  - unauthenticated RevenueCat webhook at `/v1/billing/revenuecat/webhook`
- `https://storage.nexavend.store`
  - MinIO S3 API path used for presigned receipt upload/view URLs

### Internal

- PostgreSQL service `postgres:5432`
- Redis service `redis:6379`
- RabbitMQ AMQP service `rabbitmq:5672`
- MinIO console service `minio:9001`
- Prometheus service `prometheus:9090`
- Grafana service `grafana:3000`
- Worker metrics service `expense-tracker-worker:9101`

### Admin-only

- Feature-request moderation routes under `/internal/feature-requests`
  - still require Firebase auth plus backend admin authorization
- Any future intentionally exposed Grafana or MinIO admin URL
  - not enabled by default in this phase

### Operator-only

- `kubectl port-forward` access to Prometheus, Grafana, RabbitMQ management, and MinIO console
- TLS secret management for the origin certificate
- secret rotation for database, RabbitMQ, MinIO, Firebase, LangSmith, and RevenueCat credentials

## Tightening Applied

- API ingress blocks `/metrics`, `/health/live`, and `/health/ready` from the public hostname.
- The public root route now returns only a generic service status.
- Grafana and Prometheus have no public ingress.
- MinIO console has no public ingress.
- PostgreSQL, Redis, and RabbitMQ are cluster-internal only.
- Storage ingress targets only the MinIO S3 API port, not the console port.

## Cloudflare Notes

- Use proxied DNS records for the public API and storage hostnames.
- Use Cloudflare Full (strict) with a valid origin certificate on the gateway.
- Keep the origin reachable only on the intended HTTPS entry path for the gateway/controller on `8443`.
