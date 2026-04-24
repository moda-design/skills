# Export pipeline

**Problem:** Archive every canvas on the team as a PDF. Upload each to S3 / Google Drive. Skip canvases that have an in-flight design task.

## Primitives

- `GET /v1/canvases` — cursor-paginate all canvases
- `POST /v1/canvases/{id}/export?format=pdf` — **synchronous**; returns a signed URL
- Handle `409 canvas_active_job` — back off and retry
- Upload the file bytes to your storage of choice

## TypeScript (Node 20+)

```ts
import fs from "node:fs";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

const HEADERS = {
  Authorization: `Bearer ${process.env.MODA_API_KEY!}`,
  "Moda-Version": "2026-05-01",
};
const s3 = new S3Client({ region: process.env.AWS_REGION });
const BUCKET = process.env.EXPORT_BUCKET!;

async function* listAllCanvases() {
  let cursor: string | null = null;
  for (;;) {
    const u = new URL("https://api.moda.app/v1/canvases");
    u.searchParams.set("limit", "100");
    if (cursor) u.searchParams.set("cursor", cursor);
    const { data, next_cursor } = await fetch(u, { headers: HEADERS }).then(r => r.json());
    for (const c of data) yield c;
    if (!next_cursor) return;
    cursor = next_cursor;
  }
}

async function exportWithRetry(canvasId: string, retries = 3): Promise<string | null> {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const res = await fetch(
      `https://api.moda.app/v1/canvases/${canvasId}/export?format=pdf`,
      { method: "POST", headers: HEADERS },
    );

    if (res.ok) {
      const { url } = await res.json();
      return url;
    }

    if (res.status === 409) {                                    // canvas_active_job
      const wait = Number(res.headers.get("Retry-After") ?? 10) * 1000;
      console.log(`Canvas ${canvasId}: task running; waiting ${wait / 1000}s`);
      await new Promise(r => setTimeout(r, wait));
      continue;
    }

    if (res.status === 429) {                                    // rate limit
      const wait = Number(res.headers.get("Retry-After") ?? 10) * 1000;
      await new Promise(r => setTimeout(r, wait));
      continue;
    }

    const body = await res.json().catch(() => null);
    console.error(`Canvas ${canvasId}: export failed`, body?.error);
    return null;
  }
  return null;
}

for await (const canvas of listAllCanvases()) {
  const exportUrl = await exportWithRetry(canvas.id);
  if (!exportUrl) continue;

  const bytes = Buffer.from(await (await fetch(exportUrl)).arrayBuffer());
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: `canvases/${canvas.id}.pdf`,
    Body: bytes,
    ContentType: "application/pdf",
    Metadata: { "canvas-name": canvas.name, "updated-at": canvas.updated_at },
  }));
  console.log(`Archived ${canvas.name} (${canvas.id})`);
}
```

## Python (`httpx`)

```python
import os, time, httpx, boto3

HEADERS = {
    "Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
    "Moda-Version": "2026-05-01",
}
s3 = boto3.client("s3")
BUCKET = os.environ["EXPORT_BUCKET"]

def iter_canvases(c):
    cursor = None
    while True:
        params = {"limit": 100}
        if cursor:
            params["cursor"] = cursor
        resp = c.get("/canvases", params=params).json()
        yield from resp["data"]
        cursor = resp["next_cursor"]
        if cursor is None:
            return

def export_with_retry(c, canvas_id, attempts=3):
    for _ in range(attempts):
        r = c.post(f"/canvases/{canvas_id}/export", params={"format": "pdf"})
        if r.is_success:
            return r.json()["url"]
        if r.status_code in (409, 429):
            wait = int(r.headers.get("Retry-After", 10))
            time.sleep(wait)
            continue
        print(f"export failed for {canvas_id}: {r.json().get('error')}")
        return None
    return None

with httpx.Client(base_url="https://api.moda.app/v1", headers=HEADERS, timeout=120) as c:
    for canvas in iter_canvases(c):
        url = export_with_retry(c, canvas["id"])
        if not url:
            continue
        # download and push to S3
        content = httpx.get(url, timeout=120).content
        s3.put_object(
            Bucket=BUCKET,
            Key=f"canvases/{canvas['id']}.pdf",
            Body=content,
            ContentType="application/pdf",
            Metadata={"canvas-name": canvas["name"], "updated-at": canvas["updated_at"]},
        )
        print(f"Archived {canvas['name']} ({canvas['id']})")
```

## Gotchas

- **Export is synchronous.** No task polling. One POST returns the signed URL (or a retryable `409`).
- **Signed URLs expire after 7 days.** Download and re-upload immediately — don't persist the signed URL itself.
- **`409 canvas_active_job`** is the retry signal when a design task is running on the canvas. Respect `Retry-After` (default 10s).
- **`429 rate_limited`** applies per-endpoint — `designs_export` has its own cap. Respect `Retry-After`.
- **Cursor pagination is sequential.** Can't parallelize page fetches. Parallelize the **per-canvas work** within a page instead (cap to ~4–8 concurrent exports).
- **Scope requirements:** `canvases:read` for listing, `designs:export` for the export endpoint. Team membership required — a share-token-only caller can't export.
- **Don't export the same canvas twice in a row.** If you re-run this job often, compare `updated_at` against your archive and skip unchanged canvases.

## Variant: filter by search

If you only want canvases matching a pattern:

```python
resp = c.get("/canvases/search", params={"query": "Q2 client decks", "limit": 100}).json()
```

`/canvases/search` is also cursor-paginated.

## See also

- [`../references/canvases-and-exports.md`](../references/canvases-and-exports.md) — export semantics, 409 pattern
- [`../references/pagination.md`](../references/pagination.md)
- [`../references/errors.md`](../references/errors.md) — rate-limit handling
