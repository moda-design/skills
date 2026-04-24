# Brief-to-deck (PDF intake)

**Problem:** A user uploads a brief PDF to your app. You want to produce a branded pitch deck from it and return a PPTX download URL.

## Primitives

- `POST /v1/uploads` — upload the PDF (multipart)
- `POST /v1/tasks` with `attachments: [{file_id, role: "source"}]` + `brand_kit_id` + `number_of_slides`
- Webhook OR polling to detect completion
- `POST /v1/canvases/{id}/export?format=pptx` — synchronous export

## TypeScript (Node 20+)

```ts
// server/api/generate-deck.ts
import { FastifyInstance } from "fastify";
import fs from "node:fs";

const HEADERS = {
  Authorization: `Bearer ${process.env.MODA_API_KEY!}`,
  "Moda-Version": "2026-05-01",
};

export default async function (app: FastifyInstance) {
  app.post("/generate-deck", async (req, reply) => {
    const { pdfPath, userId } = (await req.body) as { pdfPath: string; userId: string };

    // 1. upload the brief
    const form = new FormData();
    form.set("file", new Blob([fs.readFileSync(pdfPath)]), "brief.pdf");
    const uploadRes = await fetch("https://api.moda.app/v1/uploads", {
      method: "POST",
      headers: { Authorization: HEADERS.Authorization, "Moda-Version": HEADERS["Moda-Version"] },
      body: form,
    });
    const brief = await uploadRes.json();                        // { id: "file_...", ... }

    // 2. find default brand kit
    const kits = await fetch("https://api.moda.app/v1/brand-kits", { headers: HEADERS }).then(r => r.json());
    const kit = kits.data.find((k: any) => k.is_default);

    // 3. start the design task
    const task = await fetch("https://api.moda.app/v1/tasks", {
      method: "POST",
      headers: { ...HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({
        prompt:
          "Build a pitch deck from the attached brief. Use our brand styling. " +
          "Prioritize real data and quotes from the brief; do not invent specifics.",
        format: { category: "slides", width: 1920, height: 1080 },
        number_of_slides: 10,
        brand_kit_id: kit?.id,
        attachments: [
          { file_id: brief.id, role: "source", label: "Brief" },
        ],
        callback_url: "https://myapp.com/webhooks/moda",
        idempotency_key: `deck:${userId}:${brief.id}`,
      }),
    }).then(r => r.json());

    reply.send({
      message: "Generating deck — takes 2–10 minutes. You'll get a notification when it's ready.",
      task_id: task.id,
      canvas_url: task.links?.canvas ?? null,                    // useful placeholder while it cooks
    });
  });
}
```

Webhook handler (abbreviated — full handler in [`webhook-receiver.md`](./webhook-receiver.md)):

```ts
async function handleAsync(event: any) {
  if (event.type !== "task.succeeded") return;
  const canvas_id = event.data.result.canvas_id;

  // 4. export synchronously
  const exp = await fetch(
    `https://api.moda.app/v1/canvases/${canvas_id}/export?format=pptx`,
    { method: "POST", headers: HEADERS },
  ).then(r => r.json());
  // exp.url — signed URL valid 7 days

  await notifyUser(
    eventIdToUserId(event.id),
    `Your deck is ready: ${event.data.result.canvas_url}\nPPTX: ${exp.url}`,
  );
}
```

## Python (FastAPI + httpx)

```python
# server/api/generate_deck.py
import os, httpx
from fastapi import APIRouter, UploadFile, File, Form

router = APIRouter()
HEADERS = {
    "Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
    "Moda-Version": "2026-05-01",
}

@router.post("/generate-deck")
async def generate_deck(
    file: UploadFile = File(...),
    user_id: str = Form(...),
):
    async with httpx.AsyncClient(
        base_url="https://api.moda.app/v1", headers=HEADERS, timeout=60,
    ) as c:
        # 1. upload
        content = await file.read()
        brief = (await c.post(
            "/uploads",
            files={"file": (file.filename, content, file.content_type)},
        )).json()

        # 2. default brand kit
        kits = (await c.get("/brand-kits")).json()
        kit_id = next((k["id"] for k in kits["data"] if k["is_default"]), None)

        # 3. start task
        task = (await c.post("/tasks", json={
            "prompt": (
                "Build a pitch deck from the attached brief. Use our brand styling. "
                "Prioritize real data and quotes from the brief; do not invent specifics."
            ),
            "format": {"category": "slides", "width": 1920, "height": 1080},
            "number_of_slides": 10,
            "brand_kit_id": kit_id,
            "attachments": [
                {"file_id": brief["id"], "role": "source", "label": "Brief"},
            ],
            "callback_url": "https://myapp.com/webhooks/moda",
            "idempotency_key": f"deck:{user_id}:{brief['id']}",
        })).json()

    return {
        "message": "Generating deck — takes 2–10 minutes.",
        "task_id": task["id"],
    }
```

Webhook handler does the export:

```python
@app.post("/webhooks/moda")
async def moda_webhook(...):
    # ... verify signature (see webhook-receiver.md) ...
    event = json.loads(body)
    if event["type"] == "task.succeeded":
        canvas_id = event["data"]["result"]["canvas_id"]
        async with httpx.AsyncClient(base_url="https://api.moda.app/v1", headers=HEADERS) as c:
            exp = (await c.post(
                f"/canvases/{canvas_id}/export",
                params={"format": "pptx"},
            )).json()
        await notify_user(user_for_event(event["id"]),
                          canvas_url=event["data"]["result"]["canvas_url"],
                          pptx_url=exp["url"])
    return {"ok": True}
```

## Gotchas

- **`idempotency_key` encoding.** Using `{user_id}:{file_id}` means re-uploading the same PDF for the same user hits the same task (desirable — idempotent, no wasted compute). If you want a fresh task each time, include a timestamp.
- **Brief → `role: "source"`.** The agent extracts content. Passing it as `reference` would make the deck mimic the PDF's formatting — not what you want.
- **`number_of_slides` is a hint, not a hard cap.** If the brief is thin, the agent may produce fewer; if it's rich, marginally more.
- **Export is synchronous.** No polling the export. One POST, one URL.
- **Signed PPTX URL expires after 7 days.** Either surface it directly to the user (they'll click within minutes usually) or download + re-host yourself.
- **`callback_url` requires API-key auth.** This recipe runs server-side so that's fine. An OAuth / MCP caller can't set `callback_url` — they'd have to poll.
- **If `brand_kit_id` is null** (empty team), the design task still runs but without brand styling — or you can error out. Decide based on UX: for internal tools, off-brand is fine; for customer-facing, force the user to set up a brand kit first.

## See also

- [`../references/uploads.md`](../references/uploads.md) — multipart upload details
- [`../references/idempotency.md`](../references/idempotency.md) — key design
- [`../references/canvases-and-exports.md`](../references/canvases-and-exports.md) — export semantics
- [`webhook-receiver.md`](./webhook-receiver.md) — production-grade handler
- [`scheduled-generation.md`](./scheduled-generation.md) — cron-driven variant
