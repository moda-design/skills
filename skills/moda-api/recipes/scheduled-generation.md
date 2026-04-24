# Scheduled generation

**Problem:** A cron fires weekly. It should generate a branded status deck from yesterday's KPIs and post the canvas URL to a Slack channel. No human in the loop.

## Primitives

- `POST /v1/tasks` with `callback_url` + `idempotency_key`
- Webhook handler verifies signature and posts to Slack
- (Optional) `POST /v1/canvases/{id}/export` if you want a PPTX link, not just the canvas URL

## Pattern

Cron → start task with a stable `idempotency_key` → return immediately. The webhook fires 2–10 minutes later and does the Slack post.

## TypeScript (Node 20+)

Cron entry point:

```ts
// cron/weekly-deck.ts — runs via GitHub Actions / Cloud Scheduler / your runner
const MODA_API_KEY = process.env.MODA_API_KEY!;
const CALLBACK_URL = "https://myapp.com/webhooks/moda";

const isoWeek = new Date().toISOString().slice(0, 10);                // safe-enough stable key
const kpis = await fetchWeeklyKPIs();

const res = await fetch("https://api.moda.app/v1/tasks", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${MODA_API_KEY}`,
    "Moda-Version": "2026-05-01",
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    prompt: `Weekly status deck for the week of ${isoWeek}. Cover:
      - Headline metrics: ${JSON.stringify(kpis.headline)}
      - Product highlights this week
      - Next-week plan`,
    format: { category: "slides", width: 1920, height: 1080 },
    number_of_slides: 8,
    callback_url: CALLBACK_URL,
    idempotency_key: `weekly-deck:${isoWeek}`,
  }),
});

const task = await res.json();
// task.id = task_01HT9..., task.status = "queued" | "running", retry_after_ms: 3000
console.log(`Queued task ${task.id}; expect webhook to fire in 2–10 min`);
```

Webhook handler (Express):

```ts
// server/webhooks/moda.ts
import crypto from "node:crypto";
import express from "express";

const SECRET = process.env.MODA_WEBHOOK_SECRET!;
const app = express();

// raw body needed for signature verification
app.post(
  "/webhooks/moda",
  express.raw({ type: "application/json" }),
  async (req, res) => {
    const ts = req.header("x-webhook-timestamp");
    const sig = req.header("x-webhook-signature");
    if (!ts || !sig) return res.status(400).end();

    // replay protection
    if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return res.status(401).end();

    const expected = crypto
      .createHmac("sha256", SECRET)
      .update(`${ts}.${req.body.toString("utf8")}`)
      .digest("hex");
    const received = sig.replace(/^v1=/, "");
    if (
      !crypto.timingSafeEqual(Buffer.from(expected, "hex"), Buffer.from(received, "hex"))
    )
      return res.status(401).end();

    const event = JSON.parse(req.body.toString("utf8"));

    // dedupe on evt_… id (use Redis in production)
    if (await alreadyProcessed(event.id)) return res.status(200).json({ ok: true });
    await markProcessed(event.id);

    res.status(200).json({ ok: true });            // 200 fast — process async
    void processAsync(event);
  },
);

async function processAsync(event: any) {
  if (event.type === "task.succeeded") {
    const { canvas_url } = event.data.result;
    await postToSlack(`Weekly deck ready: ${canvas_url}`);
  } else if (event.type === "task.failed") {
    await postToSlack(
      `Weekly deck failed: ${event.data.error?.message ?? "unknown"} ` +
      `(request_id=${event.data.error?.request_id ?? "?"})`,
    );
  }
}
```

## Python (FastAPI + httpx)

Cron entry point:

```python
# cron/weekly_deck.py
import datetime, os, httpx, json

MODA_API_KEY = os.environ["MODA_API_KEY"]
CALLBACK_URL = "https://myapp.com/webhooks/moda"

iso_week = datetime.datetime.utcnow().strftime("%Y-W%V")
kpis = fetch_weekly_kpis()

with httpx.Client(
    base_url="https://api.moda.app/v1",
    headers={
        "Authorization": f"Bearer {MODA_API_KEY}",
        "Moda-Version": "2026-05-01",
    },
    timeout=30,
) as c:
    task = c.post("/tasks", json={
        "prompt": f"""Weekly status deck for {iso_week}.
- Headline metrics: {json.dumps(kpis['headline'])}
- Product highlights this week
- Next-week plan""",
        "format": {"category": "slides", "width": 1920, "height": 1080},
        "number_of_slides": 8,
        "callback_url": CALLBACK_URL,
        "idempotency_key": f"weekly-deck:{iso_week}",
    }).json()

print(f"Queued task {task['id']}; webhook fires in 2–10 min")
```

Webhook handler (FastAPI):

```python
# server/webhooks.py
import hashlib, hmac, os, time
from fastapi import FastAPI, Header, HTTPException, Request

app = FastAPI()
SECRET = os.environ["MODA_WEBHOOK_SECRET"]
processed: set[str] = set()                # swap for Redis in production

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
    if not hmac.compare_digest(expected, x_webhook_signature.removeprefix("v1=")):
        raise HTTPException(401, "bad signature")

    event = await req.json()
    if event["id"] in processed:
        return {"ok": True}
    processed.add(event["id"])

    # 200 fast; process async
    enqueue(event)                          # e.g. Celery / Arq / RQ
    return {"ok": True}
```

## Gotchas

- **`Prefer: wait=30` is the wrong tool** here. Design tasks take 2–10 min. The cron would time out, and the webhook still fires anyway. Use the callback pattern.
- **`idempotency_key` must be stable and unique per cron fire.** `"weekly-deck:2026-W17"` is good. `"weekly-deck"` alone is a landmine (every week reuses the same key → same task every time).
- **`callback_url` is API-key-auth only.** The cron needs a real `moda_live_…` key.
- **Slow webhook handlers get retried.** Stay under 30s wall time by enqueueing async.
- **On `task.failed`**, check `data.error.retryable` — transient failures may retry inside Moda automatically; permanent ones won't. Either way, notify a channel — failures silently swallowed are the worst case.

## See also

- [`../references/webhooks.md`](../references/webhooks.md) — signing details, event types
- [`../references/idempotency.md`](../references/idempotency.md) — key design
- [`webhook-receiver.md`](./webhook-receiver.md) — the handler in isolation
