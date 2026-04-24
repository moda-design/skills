# Webhooks

When you start a task with `POST /v1/tasks` or `POST /v1/remix`, pass a `callback_url` to receive an HTTPS POST when the task reaches terminal state. Webhooks fire **terminal-only** — there is no progress stream.

## Important auth restriction

`callback_url` is **API-key-auth only**. OAuth callers (MCP sessions) get:

```json
{ "error": { "type": "invalid_request", "code": "unsupported_auth",
  "message": "callback_url is only supported for API-key authenticated callers." } }
```

Use polling from OAuth clients.

## Event types

Closed set. If your handler sees anything outside this list, it's a bug to report.

| Event | Fires when |
| --- | --- |
| `task.succeeded` | Design or remix task finished successfully |
| `task.failed` | Task failed (transient or dead-lettered — see `data.error.retryable`) |
| `task.canceled` | Task was canceled (via `POST /v1/tasks/{id}/cancel` or app UI) |
| `export.succeeded` | Async canvas export finished (future; current exports are synchronous) |
| `export.failed` | Async export failed |

Non-terminal states (`queued`, `running`, `expired`) **do not** fire webhooks today. If you need running/progress beats, poll `GET /v1/tasks/{id}`.

## Payload

```json
{
  "id": "evt_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
  "type": "task.succeeded",
  "created": "2026-04-15T12:01:00+00:00",
  "api_version": "2026-05-01",
  "data": {
    "id": "task_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
    "kind": "design",
    "status": "succeeded",
    "result": { "canvas_id": "cvs_...", "canvas_url": "https://..." },
    ... /* full canonical Task envelope */
  }
}
```

Fields:

| Field | Notes |
| --- | --- |
| `id` | `evt_…` event ID. **Stable across retries of the same event** — use as your idempotency key. |
| `type` | One of the event types above. |
| `created` | ISO 8601 timestamp when the event was generated. |
| `api_version` | The canonical Moda-Version of the `data` payload (currently `2026-05-01`). |
| `data` | Full canonical Task envelope. Same shape as `GET /v1/tasks/{id}`. |

For `task.failed` / `export.failed`, inspect `data.error.retryable` to distinguish transient from dead-lettered failures.

## Signature verification

Every webhook POST includes two headers:

| Header | Value |
| --- | --- |
| `X-Webhook-Signature` | `v1=<hex>` — HMAC-SHA256 |
| `X-Webhook-Timestamp` | Unix seconds when the webhook was sent |

Signature is computed over `{timestamp}.{raw_body}` using the **webhook signing secret** that was shown once in **Settings → Developer → REST API** when you created the API key.

### Node.js

```js
import crypto from "node:crypto";

function verifyWebhook(signingSecret, rawBody, sigHeader, tsHeader) {
  const message = `${tsHeader}.${rawBody}`;
  const expected = crypto.createHmac("sha256", signingSecret).update(message).digest("hex");
  const received = sigHeader.replace(/^v1=/, "");
  return crypto.timingSafeEqual(
    Buffer.from(expected, "hex"),
    Buffer.from(received, "hex"),
  );
}
```

### Python

```python
import hashlib, hmac

def verify_webhook(signing_secret: str, raw_body: bytes, sig_header: str, ts_header: str) -> bool:
    message = f"{ts_header}.{raw_body.decode()}"
    expected = hmac.new(signing_secret.encode(), message.encode(), hashlib.sha256).hexdigest()
    received = sig_header.removeprefix("v1=")
    return hmac.compare_digest(expected, received)
```

Use `timingSafeEqual` / `hmac.compare_digest` — not raw `==` — to avoid timing attacks.

## Replay protection

Reject any webhook with an `X-Webhook-Timestamp` older than **5 minutes**. A valid recent signature could otherwise be replayed indefinitely.

```python
import time
if abs(time.time() - int(ts_header)) > 300:   # 5 minutes
    return 401
```

## Retry behavior

If your endpoint returns a non-2xx status or doesn't respond within **30 seconds**, Moda retries with exponential backoff:

| Attempt | Delay |
| --- | --- |
| 1st retry | 1s |
| 2nd retry | 5s |
| 3rd retry | 30s |

After three retries, the webhook is dropped. You can still fetch the task via `GET /v1/tasks/{id}`.

## Deduplication

The event envelope `id` (`evt_…`) is **stable across retries of the same event**. Use it as your dedupe key:

```python
# pseudocode
if processed_events.contains(event["id"]):
    return 200        # acknowledge; already handled
processed_events.add(event["id"])
handle(event)
return 200
```

Retries of the *same* event carry the same `id`. Different events (e.g. `task.succeeded` for two different tasks) have different `id`s — they're not dedupe-collisions.

## Handler best practices

1. **Return 200 fast.** Process asynchronously — enqueue the event, don't do the work inline. Moda's 30s timeout will retry if you're slow.
2. **Verify signature before trusting the payload.** Even for non-sensitive work.
3. **Check the timestamp** (>5 min old → reject).
4. **Use `evt_…` as your idempotency key.**
5. **HTTPS only.** Moda rejects non-HTTPS callback URLs up front.
6. **Log `request_id`** from the task envelope inside `data` when reporting issues.

## End-to-end handler (Python + FastAPI)

```python
from fastapi import FastAPI, Header, HTTPException, Request
import os, time, hashlib, hmac

app = FastAPI()
SECRET = os.environ["MODA_WEBHOOK_SECRET"]

processed = set()                                 # use Redis / DB in production

@app.post("/webhooks/moda")
async def moda_webhook(
    req: Request,
    x_webhook_signature: str = Header(...),
    x_webhook_timestamp: str = Header(...),
):
    body = await req.body()
    if abs(time.time() - int(x_webhook_timestamp)) > 300:
        raise HTTPException(401, "stale timestamp")

    expected = hmac.new(
        SECRET.encode(),
        f"{x_webhook_timestamp}.{body.decode()}".encode(),
        hashlib.sha256,
    ).hexdigest()
    received = x_webhook_signature.removeprefix("v1=")
    if not hmac.compare_digest(expected, received):
        raise HTTPException(401, "bad signature")

    event = await req.json()
    if event["id"] in processed:
        return {"ok": True}
    processed.add(event["id"])

    # enqueue async; return 200 fast
    enqueue_task(event)
    return {"ok": True}
```

See [`../recipes/webhook-receiver.md`](../recipes/webhook-receiver.md) for both Node/Express and FastAPI worked examples with enqueue + retry plumbing.

## Common wrong guesses

- **Using `callback_url` from an OAuth/MCP session.** Rejected. API-key auth only.
- **Expecting `task.running` / `task.queued` events.** Terminal-only today.
- **Using raw `==` to compare signatures.** Timing-attack risk. Use `hmac.compare_digest` / `crypto.timingSafeEqual`.
- **Not verifying timestamp age.** Replayable. Reject >5 min.
- **Doing work inside the handler.** 30s timeout will re-fire retries. Enqueue, then 200.
- **Forgetting the signing secret.** It's shown once with the API key. Store it in your secret manager alongside the key.
- **Handling retries as new events.** Same `evt_…` id → same event. Dedupe.

## Upstream

- [`docs.moda.app/api/webhooks`](https://docs.moda.app/api/webhooks)
- [`authentication.md`](./authentication.md) — where the signing secret comes from
