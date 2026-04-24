# Webhook receiver

**Problem:** Stand up a production-grade endpoint that verifies Moda webhook signatures, rejects replays, deduplicates, acknowledges fast, and hands off event processing to a background worker.

## Primitives

- Raw request body (for HMAC)
- `X-Webhook-Signature` + `X-Webhook-Timestamp` headers
- Webhook signing secret (stored with the API key — **not** the API key itself)
- Event envelope `id` as the dedupe key
- Async worker (queue / task runner / Pub-Sub topic) for the actual work

## TypeScript — Express

```ts
// server/webhooks/moda.ts
import express from "express";
import crypto from "node:crypto";
import { createClient } from "redis";                // use your dedupe store of choice

const app = express();
const SECRET = process.env.MODA_WEBHOOK_SECRET!;
const redis = createClient({ url: process.env.REDIS_URL });
await redis.connect();

// IMPORTANT: use express.raw here, NOT express.json — we need the exact bytes for HMAC.
app.post(
  "/webhooks/moda",
  express.raw({ type: "application/json", limit: "1mb" }),
  async (req, res) => {
    const tsHeader = req.header("x-webhook-timestamp");
    const sigHeader = req.header("x-webhook-signature");
    if (!tsHeader || !sigHeader) return res.status(400).end();

    // 1. replay protection
    const skew = Math.abs(Date.now() / 1000 - Number(tsHeader));
    if (!Number.isFinite(skew) || skew > 300) return res.status(401).end();

    // 2. signature verification
    const expected = crypto
      .createHmac("sha256", SECRET)
      .update(`${tsHeader}.${req.body.toString("utf8")}`)
      .digest("hex");
    const received = sigHeader.replace(/^v1=/, "");
    const sigOk =
      expected.length === received.length &&
      crypto.timingSafeEqual(
        Buffer.from(expected, "hex"),
        Buffer.from(received, "hex"),
      );
    if (!sigOk) return res.status(401).end();

    // 3. parse + dedupe on event id
    const event = JSON.parse(req.body.toString("utf8"));
    const dedupeKey = `moda:evt:${event.id}`;
    const firstTime = await redis.set(dedupeKey, "1", { NX: true, EX: 60 * 60 * 24 * 7 });
    if (!firstTime) return res.status(200).json({ ok: true });          // already handled

    // 4. ack fast; process in the background
    res.status(200).json({ ok: true });
    void handleAsync(event);
  },
);

async function handleAsync(event: any) {
  try {
    switch (event.type) {
      case "task.succeeded": {
        const { canvas_url } = event.data.result;
        await notifySuccess(event.data.id, canvas_url);
        break;
      }
      case "task.failed": {
        const retryable = event.data.error?.retryable ?? false;
        await notifyFailure(event.data.id, event.data.error?.message, retryable);
        break;
      }
      case "task.canceled":
      case "export.succeeded":
      case "export.failed":
        // handle as needed
        break;
      default:
        // unexpected event type → log for ops, not for the user
        console.warn("Unknown Moda event type", event.type, event.id);
    }
  } catch (e) {
    console.error("Handler threw", e, "event=", event.id);
    // do not re-throw — webhook was already acked
  }
}
```

## Python — FastAPI

```python
# server/webhooks/moda.py
import hashlib, hmac, json, os, time
from fastapi import FastAPI, Header, HTTPException, Request
from redis.asyncio import Redis

app = FastAPI()
SECRET = os.environ["MODA_WEBHOOK_SECRET"]
redis = Redis.from_url(os.environ["REDIS_URL"])

@app.post("/webhooks/moda")
async def moda_webhook(
    req: Request,
    x_webhook_signature: str = Header(...),
    x_webhook_timestamp: str = Header(...),
):
    body = await req.body()

    # 1. replay protection
    try:
        skew = abs(time.time() - int(x_webhook_timestamp))
    except ValueError:
        raise HTTPException(401, "bad timestamp")
    if skew > 300:
        raise HTTPException(401, "stale timestamp")

    # 2. signature verification
    expected = hmac.new(
        SECRET.encode(),
        f"{x_webhook_timestamp}.{body.decode()}".encode(),
        hashlib.sha256,
    ).hexdigest()
    received = x_webhook_signature.removeprefix("v1=")
    if not hmac.compare_digest(expected, received):
        raise HTTPException(401, "bad signature")

    # 3. dedupe on event id
    event = json.loads(body)
    first_time = await redis.set(
        f"moda:evt:{event['id']}", "1", nx=True, ex=60 * 60 * 24 * 7,
    )
    if not first_time:
        return {"ok": True}

    # 4. enqueue async work; return fast
    await enqueue(event)                       # e.g. Celery, Arq, RQ, Pub/Sub
    return {"ok": True}


async def enqueue(event: dict) -> None:
    # Your enqueue implementation. Must return in < a few seconds.
    ...
```

## What to do per event type

```
task.succeeded  → grab data.result.canvas_url, notify the user / CRM / Slack
task.failed     → check data.error.retryable:
                  - retryable true: transient; task already dead-lettered after N attempts
                  - retryable false: permanent; surface to the user
task.canceled   → quiet path; log only, or notify if cancellation was unexpected
export.succeeded → grab data.result.export_url (future; current exports are sync)
export.failed    → same failure-handling as task.failed
```

Always log `data.error.request_id` on failures — it's the handle support will use to find your request.

## Gotchas

- **Use raw body** for HMAC. Express / FastAPI default JSON parsing hides the exact bytes. `express.raw` or `await req.body()` (not `await req.json()` before reading body).
- **Return 200 in < 30s**, always. Moda retries non-2xx or timeouts at 1s / 5s / 30s.
- **Dedupe on `event.id`**, not `event.data.id`. Same task can have multiple events (succeeded vs failed, though rare; future: export for the same task). Using `event.id` dedupes **retries of the same event**; using `task.id` would dedupe legitimate different events.
- **TTL your dedupe keys.** 7 days is plenty — Moda's retry window is minutes.
- **Reject stale timestamps.** 5 minutes is the conventional bound. Anything older is almost certainly a replay attack.
- **Use constant-time compare** (`timingSafeEqual` / `compare_digest`). Raw `==` leaks timing info.
- **HTTPS only.** Moda won't deliver to plain-HTTP `callback_url`.
- **Don't do work inside the handler.** Enqueue, then 200. If Postgres is down or Slack is slow, you want to 200 anyway and retry the downstream work yourself — not force Moda to retry.
- **Test with the wrong signature** in staging to make sure you reject. A handler that silently accepts unsigned bodies is the worst case.

## Local testing without public HTTPS

```
ngrok http 3000           # or `tailscale serve` / `cloudflared tunnel`
```

Point the task's `callback_url` at the ngrok HTTPS URL. Signing still works — the signing secret is per-API-key, not per-URL.

## See also

- [`../references/webhooks.md`](../references/webhooks.md) — full event list, retry curve
- [`scheduled-generation.md`](./scheduled-generation.md) — the cron that produces the task
- [`../references/authentication.md`](../references/authentication.md) — where the signing secret comes from
