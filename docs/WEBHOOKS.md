# Webhooks

## RevenueCat

The backend now exposes a production-oriented RevenueCat webhook endpoint:

- Path: `/v1/billing/revenuecat/webhook`
- Auth: shared secret header defined by `REVENUECAT_WEBHOOK_AUTH_HEADER`
- Secret value: `REVENUECAT_WEBHOOK_AUTH_SECRET`

## Safety Properties

- Webhook auth is mandatory when the endpoint is used.
- Deliveries are idempotent through the `billing_webhook_events` table.
- Duplicate processed events return a successful duplicate response instead of replaying work.
- Unknown `app_user_id` values are ignored safely and recorded for operator visibility.
- The endpoint does not log raw payload bodies.
- The handler reuses the existing RevenueCat sync flow instead of maintaining a second billing state machine.

## Operator Setup

1. Set `REVENUECAT_SECRET_API_KEY`.
2. Set `REVENUECAT_WEBHOOK_AUTH_HEADER`.
3. Set `REVENUECAT_WEBHOOK_AUTH_SECRET`.
4. Configure the RevenueCat dashboard webhook target to:
   `https://api.nexavend.store:8443/v1/billing/revenuecat/webhook`
5. Configure RevenueCat to send the matching secret in the configured header.

## Verification

Recommended checks after deployment:

1. Send a RevenueCat test webhook.
2. Confirm the API returns `200`.
3. Inspect backend logs for `revenuecat_webhook_processed`, `revenuecat_webhook_ignored`, or `revenuecat_webhook_failed`.
4. Confirm `billing_webhook_events` contains the delivery record.
5. Confirm the affected user subscription row updated in `subscriptions`.

## Retry Behavior

- Successful processing returns `200`.
- Duplicate processed events return `200`.
- Invalid auth returns `403`.
- Missing configuration returns `503`.
- Upstream sync failures return a non-success response so the sender can retry.
