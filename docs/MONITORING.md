# Monitoring

This phase adds three complementary observability layers:

- Application logs from the API and receipt worker.
- Prometheus metrics with an internal Grafana dashboard.
- LangSmith traces for the AI receipt extraction path.

## What Is Exposed

- API metrics: served by the backend at `METRICS_API_PATH` and scraped internally by Prometheus.
- Worker metrics: served internally on `WORKER_METRICS_PORT` through the `expense-tracker-worker` service.
- Prometheus UI: internal-only `prometheus` service on port `9090`.
- Grafana UI: internal-only `grafana` service on port `3000`.
- LangSmith: outbound-only integration to the configured LangSmith endpoint.

The public API ingress explicitly blocks `/metrics` by default. If you change `METRICS_API_PATH`, update the ingress restriction in `infra/k8s/overlays/production/ingress.yaml` at the same time.

## Metrics Included

- API request count by method/path/status.
- API request latency histogram.
- API dependency health gauges for PostgreSQL, Redis, and RabbitMQ.
- Worker jobs started, completed, failed, retries, and in-progress count.
- Receipt processing duration histogram.
- Receipt extraction success/failure and latency.
- RevenueCat webhook outcomes.
- Worker dependency gauges for database, RabbitMQ, and MinIO/S3.

## Grafana Access

Grafana is provisioned with:

- A Prometheus datasource pointing at `http://prometheus:9090`.
- A preloaded `AI Expense Tracker Overview` dashboard.

Recommended operator access for a single VPS:

1. `kubectl -n expense-tracker port-forward svc/grafana 3000:3000`
2. Sign in with `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD`.

Prometheus can be inspected the same way:

1. `kubectl -n expense-tracker port-forward svc/prometheus 9090:9090`

## LangSmith

LangSmith is controlled entirely by environment variables:

- `LANGSMITH_TRACING`
- `LANGSMITH_API_KEY`
- `LANGSMITH_PROJECT`
- `LANGSMITH_ENDPOINT`
- `LANGSMITH_HIDE_INPUTS`
- `LANGSMITH_HIDE_OUTPUTS`

Receipt tracing is intentionally redacted by default:

- raw receipt image bytes are not sent as trace inputs
- raw prompt text is not sent as trace inputs
- raw parsed receipt output is not sent as trace outputs
- metadata keeps safe correlation fields such as receipt id, attempt, provider, model, latency, and item count

## Render And Deploy

1. Fill `.env.production`.
2. Run `python infra/k8s/scripts/render_k8s_env.py --env-file .env.production`.
3. Apply `kubectl apply -k infra/k8s/overlays/production`.

The render step writes:

- `infra/k8s/overlays/production/generated/prometheus.yml`

Prometheus uses that generated file as its scrape configuration, so operator changes to scrape/evaluation intervals live in `.env.production`.
