# Idempotency

`POST /v1/tasks` accepts an optional `idempotency_key` in the request body. Reusing the same key returns the existing task instead of creating a duplicate.

## When to use

- **Scheduled jobs.** Cron fires at 9am Monday. Use `idempotency_key: "weekly-deck:2026-W17"`. If your worker crashes after the POST succeeds but before writing the response, the next retry returns the same task.
- **Network-timeout retries.** Your HTTP client times out mid-POST. Retry with the same key — safe.
- **Upstream-triggered flows.** A Slack command fires two webhooks on the same action. Use the slack message ID as the key: `idempotency_key: "slack:T01234:123456.789"`.
- **Bulk fan-out.** 50 prospects × one task each. `idempotency_key: "prospect:{id}:2026-04-weekly"` keeps re-runs safe.

## How it works

```
POST /v1/tasks
{ "prompt": "…", "idempotency_key": "focustime-v1", ... }
```

- First call: creates the task, returns the envelope.
- Second call with the same key **and identical body**: returns the same envelope.
- Second call with the same key **but a different body**: returns `409 idempotency_conflict`.

No dedicated "I'm reusing" flag on the response — the `id` matches the original, that's how you can tell.

## Conflict handling

```json
{
  "error": {
    "type": "conflict",
    "code": "idempotency_conflict",
    "message": "An existing task is associated with idempotency_key 'focustime-v1' but with a different request body.",
    "request_id": "019d8996-…"
  }
}
```

Fix one of:

- Use a different `idempotency_key` for the new body.
- Change your code so the body is byte-identical (e.g. canonicalize attachment order, don't include a timestamp in the prompt).

## Key design

- **Stable and unique per logical operation.** "weekly-deck" alone is bad (reused every week); `"weekly-deck:2026-W17"` is good.
- **Hash complex inputs** if the key would otherwise be long: `sha256(prompt + brand_kit_id + format)`. Deterministic + short.
- **Scope to your own integration.** Keys are per-API-key, so namespacing isn't strictly required, but `"myapp:weekly-deck:2026-W17"` is clearer in debug logs.
- **TTL.** Moda retains idempotency records long enough to cover sensible retry windows — don't rely on a specific duration. If you're retrying a week later, use a different key.

## Not wired (yet)

- **`Idempotency-Key` HTTP header** (Stripe-style). Today, `idempotency_key` is a **body field**. A header-based variant is on the roadmap; when it lands, existing body-field usage continues to work.
- **Idempotency on other endpoints.** Only `POST /v1/tasks` accepts `idempotency_key` today. Other writes (`POST /v1/brand-kits`, `POST /v1/uploads`) are not idempotent — retrying may create duplicates. `POST /v1/uploads` does dedupe by content hash (`was_duplicate: true`) which gives similar safety without the explicit key.

## Webhook idempotency (separate concern)

Webhook **receivers** should use the event envelope's `id` (`evt_…`) as the dedupe key. That's about guarding your handler against duplicate deliveries — a different concern from `idempotency_key` on task creation. See [`webhooks.md`](./webhooks.md).

## Worked example — weekly cron

```python
iso_week = datetime.utcnow().strftime("%Y-W%V")                 # e.g. "2026-W17"
resp = httpx.post(
    "https://api.moda.app/v1/tasks",
    headers=HEADERS,
    json={
        "prompt": build_weekly_prompt(),
        "format": {"category": "slides", "width": 1920, "height": 1080},
        "number_of_slides": 10,
        "callback_url": "https://myapp.com/webhooks/moda",
        "idempotency_key": f"weekly-deck:{iso_week}",
    },
)
# safe to retry this whole call on network error — same key, same body
```

## Common wrong guesses

- **Using an `Idempotency-Key` HTTP header.** Not supported today. Use the body field `idempotency_key`.
- **Reusing the same key across different operations.** "default" as the key for every task. You'll just keep getting back the first task you ever created with that key.
- **Changing the body and reusing the key.** `409 idempotency_conflict`. Change one or the other.
- **Assuming idempotency extends to non-task endpoints.** `POST /v1/brand-kits` with the same URL twice creates two separate brand-kit-extract tasks (unless cached). Only `POST /v1/tasks` takes `idempotency_key`.

## Upstream

- [`docs.moda.app/api/tasks/startTask`](https://docs.moda.app/api/tasks/startTask) — parameter reference
- [`errors.md`](./errors.md) — the full error envelope including `idempotency_conflict`
