# Versioning

Moda's API uses a calendar-dated version string on the `Moda-Version` request header. Pinning guarantees your wire shape stays stable.

## Supported versions (as of 2026-04-24)

| Version | Role | Status | Sunsets |
| --- | --- | --- | --- |
| `2026-05-01` | **Canonical** (newest) | Latest response shape | — |
| `2026-04-12` | **Default** (legacy) | What unpinned traffic resolves to | **2026-05-12** |

- **Canonical** = routes emit this shape natively. Pin this in production.
- **Default** = what unpinned requests get. Advances to the next-newest supported version on sunset dates.
- **Sunset** = after this date, pinning the sunset version returns `400 unsupported_version`.

## Sending the header

```
Moda-Version: 2026-05-01
```

Pin explicitly on every request. Don't rely on the default.

## Omitting

If you omit the header, the server resolves to the current **default**. Integrations keep working across version bumps until a sunset advances the default. **For production, pin.**

## Unknown version

```json
{
  "error": {
    "type": "invalid_request",
    "code": "unsupported_version",
    "message": "Moda-Version '2026-01-01' is not supported. Supported versions: 2026-04-12, 2026-05-01.",
    "details": {
      "requested": "2026-01-01",
      "supported": ["2026-04-12", "2026-05-01"]
    },
    "request_id": "019d8996-…"
  }
}
```

Read `details.supported` — that's the ground truth, and it updates automatically.

## Response header

Every response carries the resolved version:

```
HTTP/1.1 200 OK
Moda-Version: 2026-05-01
```

If you omit the request header, read the response's `Moda-Version` to know which shape you got.

## Canonical (`2026-05-01`) vs legacy (`2026-04-12`)

### Task endpoints

**Legacy flat shape (`2026-04-12`):**

```json
{
  "job_id": "task_01HT9...",
  "status": "completed",
  "canvas_id": "cvs_...",
  "canvas_url": "https://...",
  "conversation_id": null,
  "task": "Create a sales deck",
  "progress_percent": 100,
  "is_terminal": true,
  "can_export": true,
  "retry_after_seconds": null,
  ...
}
```

**Canonical Task envelope (`2026-05-01`):**

```json
{
  "id": "task_01HT9...",
  "kind": "design",
  "status": "succeeded",
  "input": { "prompt": "Create a sales deck" },
  "result": { "canvas_id": "cvs_...", "canvas_url": "https://..." },
  "progress": null,
  "error": null,
  "credits": { "credits_used": 5, "credits_remaining": 12 },
  "links": { "self": "/v1/tasks/...", "cancel": null, "canvas": "..." },
  "retry_after_ms": null
}
```

Migration map:

| Legacy | Canonical |
| --- | --- |
| `response.job_id` | `response.id` |
| `response.status == "completed"` | `response.status == "succeeded"` |
| `response.status == "cancelled"` | `response.status == "canceled"` |
| `response.canvas_id` | `response.result.canvas_id` |
| `response.canvas_url` | `response.result.canvas_url` |
| `response.conversation_id` | `response.result.conversation_id` |
| `response.task` | `response.input.prompt` |
| `response.progress_percent` | `response.progress.percent` |
| `response.current_step` | `response.progress.step` |
| `response.error` (string) | `response.error.message` (object) |
| `response.is_terminal` | derived: `status in ("succeeded","failed","canceled","expired")` |
| `response.can_export` | derived: `status == "succeeded" && result.canvas_id` |
| `response.retry_after_seconds` | `response.retry_after_ms / 1000` |

### List endpoints: offset → cursor

**Legacy:**

```json
{ "canvases": [...], "total": 123, "offset": 20, "limit": 20, "has_more": true }
```

**Canonical:**

```json
{ "data": [...], "next_cursor": "eyJ2..." }
```

Iterate until `next_cursor === null`. See [`pagination.md`](./pagination.md).

### Webhook events

Legacy `job.*` names are retired in favor of `task.*` / `export.*`. Spelling changed: `cancelled` → `canceled` (matches the `PublicTaskStatus.CANCELED` enum). Non-terminal states (`queued`, `running`, `expired`) no longer fire webhooks.

| Legacy | Canonical |
| --- | --- |
| `job.completed` | `task.succeeded` |
| `job.failed` | `task.failed` |
| `job.cancelled` | `task.canceled` |
| `job.dead_letter` | `task.failed` with `data.error.retryable: false` |
| `job.running` | removed (poll `/v1/tasks/{id}`) |
| `job.queued` | removed |

## What triggers a new version

Only **breaking** response-shape changes. Additive changes (new endpoints, new optional params, new response fields) ship at the current canonical version without a bump.

Breaking:
- Removing / renaming a response field
- Removing an endpoint or path
- Changing a field's type
- Tightening validation
- Changing status vocabulary

Additive (no bump):
- New endpoint / path / optional param / response field
- New error `code` within an existing `type`

Tolerate unknown fields in your client.

## Version-bump cadence

- New canonical arrives.
- Previous default stays supported for a sunset window (usually 2–3 weeks).
- On the sunset date, the older version retires; default advances.
- If you pinned, you upgrade on your schedule.

## Recommendations

- **Pin** `Moda-Version` explicitly on every production request.
- **Log the response `Moda-Version`** so you can tell which shape your traffic is actually hitting.
- **When you see `400 unsupported_version`**, read `details.supported` from the error.
- **Subscribe to the Moda changelog** for sunset dates.

## Common wrong guesses

- **Omitting `Moda-Version` in production.** The default will advance on sunset and your response shape will silently change.
- **Parsing legacy `job_id` / `canvas_id` from canonical responses.** They're nested under `id` and `result.canvas_id`.
- **Spelling `cancelled` with two Ls.** Canonical spelling is `canceled` (one L). `cancelled` is a legacy artifact.
- **Assuming a sunset version still works.** After the sunset date, pinning it returns `400`.

## Upstream

[`docs.moda.app/api/versioning`](https://docs.moda.app/api/versioning)
