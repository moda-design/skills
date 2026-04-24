# Uploads

Two endpoints. Both require `uploads:write`.

## Entrypoints

### `POST /v1/uploads` — multipart

```bash
curl -X POST https://api.moda.app/v1/uploads \
  -H "Authorization: Bearer moda_live_..." \
  -H "Moda-Version: 2026-05-01" \
  -F "file=@/path/to/brief.pdf"
```

Response:

```json
{
  "id": "file_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
  "url": "https://api.moda.app/api/v2/images/ref/550e8400-...?h=abc123",
  "filename": "brief.pdf",
  "mime_type": "application/pdf",
  "size_bytes": 245760,
  "was_duplicate": false
}
```

Use when you have the bytes locally.

### `POST /v1/uploads/from-url`

```bash
curl -X POST https://api.moda.app/v1/uploads/from-url \
  -H "Authorization: Bearer moda_live_..." \
  -H "Moda-Version: 2026-05-01" \
  -H "Content-Type: application/json" \
  -d '{"source_url": "https://example.com/mockup.png"}'
```

Server fetches the URL, validates MIME, stores. Returns the same `FileUploadResponse` shape. Use when the file is already hosted publicly and you don't want to proxy it through your own machine.

SSRF-validated server-side — internal / localhost / metadata URLs are rejected with `422`.

## Supported types

- Images: PNG, JPEG, WebP
- Documents: PDF, PPTX

The server enforces a max file size (multiple MB, varies by plan). Oversize uploads return `422 unprocessable`.

## Deduplication

Content-hash dedupe. Uploading the same bytes twice returns:

```json
{ "id": "file_01HT9...", "was_duplicate": true, ... }
```

`id` / `url` / `filename` / `mime_type` / `size_bytes` point at the existing record. Safe to call repeatedly — no duplicate storage, no duplicate billing.

## Using in a task

```bash
curl -X POST https://api.moda.app/v1/tasks \
  -H "Authorization: Bearer moda_live_..." \
  -H "Moda-Version: 2026-05-01" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Build a pitch deck from the attached brief",
    "format": { "category": "slides", "width": 1920, "height": 1080 },
    "attachments": [
      { "file_id": "file_01HT9WK8...", "role": "source", "label": "Q2 strategy brief" }
    ]
  }'
```

### Roles

| Role | Meaning |
| --- | --- |
| `source` | Extract content from this file (brief, notes, CSV) |
| `reference` | Emulate this file's style (mood board, screenshot) |
| `asset` | Use verbatim (logo, hero image) |

Pick the right role — it determines what the agent does with the file. See `moda-mcp/references/attachments.md` for details; the attachment shape is identical between MCP and REST.

## URL-form attachment (legacy, less preferred)

```json
{
  "attachments": [
    { "url": "https://example.com/mockup.png", "type": "image" }
  ]
}
```

No role metadata. Still works for hosted public URLs when you want to avoid the upload roundtrip. Mix with file-id-form in the same list freely.

## Worked example

```python
import httpx, os

HEADERS = {"Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
           "Moda-Version": "2026-05-01"}

with httpx.Client(base_url="https://api.moda.app/v1", headers=HEADERS, timeout=60) as c:
    with open("brief.pdf", "rb") as f:
        upload = c.post("/uploads", files={"file": ("brief.pdf", f, "application/pdf")}).json()

    task = c.post("/tasks", json={
        "prompt": "Build a 10-slide pitch deck from the brief",
        "format": {"category": "slides", "width": 1920, "height": 1080},
        "number_of_slides": 10,
        "attachments": [
            {"file_id": upload["id"], "role": "source", "label": "Q2 strategy"},
        ],
        "idempotency_key": "q2-strategy-deck-v1",
    }).json()
```

## Common wrong guesses

- **Posting files as JSON-encoded base64 into `POST /v1/uploads`.** Use multipart (`multipart/form-data`).
- **Using the proxy URL (`/api/v2/images/ref/…`) as if it were stable public content.** It includes an auth hash; it's a stable reference for use in Moda-side operations, not a CDN URL.
- **Re-uploading on every run when content hasn't changed.** Dedupe handles it server-side, but you still pay a roundtrip. Cache `file_id` in your app.
- **Skipping `role` in the attachment.** It drops back to a generic "reference" semantic, which is usually not what you want. Always set `role`.
- **Mixing `file_id` and `url` in one attachment item.** Pick one per item. Mix items within the array is fine.

## Upstream

- [`docs.moda.app/api/uploads/uploadFile`](https://docs.moda.app/api/uploads/uploadFile)
- [`docs.moda.app/api/uploads/uploadFromUrl`](https://docs.moda.app/api/uploads/uploadFromUrl)
