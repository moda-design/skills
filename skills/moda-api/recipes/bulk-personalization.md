# Bulk personalization

**Problem:** You have a CSV of 50 prospects. Produce one personalized follow-up deck per prospect, using an uploaded brief as the content source and the team's default brand kit. Collect the canvas URLs when they're done.

## Primitives

- `POST /v1/uploads` — upload the shared brief (once)
- `POST /v1/tasks` — fan out one task per prospect with `idempotency_key`
- `callback_url` webhook — receive terminal state per task (preferred) OR polling pool (fallback)

## TypeScript (Node 20+, `fetch`)

```ts
import fs from "node:fs";
import Papa from "papaparse";

const HEADERS = {
  Authorization: `Bearer ${process.env.MODA_API_KEY!}`,
  "Moda-Version": "2026-05-01",
  "Content-Type": "application/json",
};
const CALLBACK_URL = "https://myapp.com/webhooks/moda";

// 1. upload the brief once
const briefForm = new FormData();
briefForm.set("file", new Blob([fs.readFileSync("brief.pdf")]), "brief.pdf");
const brief = await fetch("https://api.moda.app/v1/uploads", {
  method: "POST",
  headers: { Authorization: HEADERS.Authorization, "Moda-Version": HEADERS["Moda-Version"] },
  body: briefForm,
}).then(r => r.json());
// brief.id = "file_01HT9..."

// 2. fan out — one task per prospect
const csv = Papa.parse(fs.readFileSync("prospects.csv", "utf8"), { header: true });
const kits = await fetch("https://api.moda.app/v1/brand-kits", { headers: HEADERS }).then(r => r.json());
const defaultKit = kits.data.find((k: any) => k.is_default);

const results: { prospect: string; task_id: string }[] = [];

for (const row of csv.data as any[]) {
  const res = await fetch("https://api.moda.app/v1/tasks", {
    method: "POST",
    headers: HEADERS,
    body: JSON.stringify({
      prompt: `Personalized follow-up deck for ${row.company}.
Prospect: ${row.contact_name}, ${row.contact_role}.
Their focus area: ${row.focus_area}.
Use the attached brief as the source of truth for our product claims.`,
      format: { category: "slides", width: 1920, height: 1080 },
      number_of_slides: 8,
      brand_kit_id: defaultKit?.id,
      attachments: [
        { file_id: brief.id, role: "source", label: "Master brief" },
      ],
      callback_url: CALLBACK_URL,
      idempotency_key: `prospect-deck:${row.id}`,          // stable per prospect
    }),
  });

  if (res.status === 429) {
    // rate limited — respect Retry-After and retry this prospect
    const waitSec = Number(res.headers.get("Retry-After") ?? 10);
    await new Promise(r => setTimeout(r, waitSec * 1000));
    // simpler: push back onto the queue; full rate-limit handling left as an exercise
  }

  const task = await res.json();
  results.push({ prospect: row.company, task_id: task.id });
}

fs.writeFileSync("tasks.json", JSON.stringify(results, null, 2));
console.log(`Queued ${results.length} tasks. Webhook will deliver results.`);
```

Webhook handler (same shape as [`webhook-receiver.md`](./webhook-receiver.md)) looks up `event.data.id` in `tasks.json`, matches it to a prospect, writes the canvas URL to a CRM / database / Slack.

## Python (`httpx`)

```python
import csv, os, httpx

HEADERS = {
    "Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
    "Moda-Version": "2026-05-01",
}

with httpx.Client(base_url="https://api.moda.app/v1", headers=HEADERS, timeout=60) as c:
    # 1. upload shared brief
    with open("brief.pdf", "rb") as f:
        brief = c.post(
            "/uploads",
            files={"file": ("brief.pdf", f, "application/pdf")},
        ).json()

    # 2. find default brand kit
    kits = c.get("/brand-kits").json()
    default_kit_id = next(
        (k["id"] for k in kits["data"] if k["is_default"]),
        None,
    )

    # 3. fan out
    results = []
    with open("prospects.csv") as f:
        for row in csv.DictReader(f):
            resp = c.post("/tasks", json={
                "prompt": (
                    f"Personalized follow-up deck for {row['company']}.\n"
                    f"Prospect: {row['contact_name']}, {row['contact_role']}.\n"
                    f"Their focus area: {row['focus_area']}.\n"
                    "Use the attached brief as the source of truth for our product claims."
                ),
                "format": {"category": "slides", "width": 1920, "height": 1080},
                "number_of_slides": 8,
                "brand_kit_id": default_kit_id,
                "attachments": [
                    {"file_id": brief["id"], "role": "source", "label": "Master brief"},
                ],
                "callback_url": "https://myapp.com/webhooks/moda",
                "idempotency_key": f"prospect-deck:{row['id']}",
            })
            if resp.status_code == 429:
                # respect Retry-After then re-queue this prospect (omitted for brevity)
                continue
            task = resp.json()
            results.append({"prospect": row["company"], "task_id": task["id"]})

    # store task_id → prospect mapping for the webhook handler to look up
    with open("tasks.json", "w") as f:
        import json
        json.dump(results, f, indent=2)
```

## Polling fallback (no webhook server)

If you can't run a webhook receiver, poll all 50 tasks in a concurrency-capped pool instead:

```python
import asyncio, time

async def poll(c: httpx.AsyncClient, task_id: str):
    while True:
        t = (await c.get(f"/tasks/{task_id}")).json()
        if t["status"] in {"succeeded", "failed", "canceled", "expired"}:
            return t
        await asyncio.sleep((t.get("retry_after_ms") or 3000) / 1000)

async def main(task_ids: list[str]):
    sem = asyncio.Semaphore(8)                       # cap parallelism
    async def guarded(tid):
        async with sem:
            return await poll(c, tid)
    async with httpx.AsyncClient(base_url="https://api.moda.app/v1", headers=HEADERS) as c:
        return await asyncio.gather(*(guarded(t) for t in task_ids))
```

## Gotchas

- **`idempotency_key` per prospect + run.** `"prospect-deck:{id}"` works if each prospect only gets one deck per logical run. If you re-run monthly, include the month: `"prospect-deck:{id}:2026-04"`.
- **Rate limits are real.** If you fan out 50 tasks in a tight loop, you may hit a per-key or per-team cap. Back off on `429` using `Retry-After`. Serialize if recurring.
- **`brand_kit_id` is the team default** by default (so you can technically omit it). Passing it explicitly makes the code's intent clear and future-proofs it if the team adds more kits.
- **Don't poll AND have a webhook.** Pick one. Doubling up wastes your rate budget and may trigger two Slack pings.
- **On task failure**, you need a way to surface which prospect failed. The `idempotency_key` or the mapping file is your link.

## See also

- [`../references/idempotency.md`](../references/idempotency.md)
- [`../references/uploads.md`](../references/uploads.md) — multipart vs from-URL
- [`webhook-receiver.md`](./webhook-receiver.md) — the webhook handler in isolation
- [`scheduled-generation.md`](./scheduled-generation.md) — single-task pattern for comparison
