# Task envelope

Every task-shaped operation — design, export (when async), remix, brand-kit extraction — returns the canonical Task envelope. Pin `Moda-Version: 2026-05-01` to get this shape.

## Full shape

```json
{
  "id": "task_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
  "kind": "design",
  "status": "queued",
  "created_at": "2026-04-15T12:00:00+00:00",
  "started_at": null,
  "completed_at": null,
  "progress": null,
  "attempt": 1,
  "max_attempts": 3,
  "input": { "prompt": "Create a sales deck", "format": { "category": "slides", ... } },
  "result": null,
  "error": null,
  "credits": null,
  "links": {
    "self": "/v1/tasks/task_01HT9...",
    "events": null,
    "cancel": "/v1/tasks/task_01HT9.../cancel",
    "canvas": null
  },
  "retry_after_ms": 3000
}
```

## Fields

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | `task_`-prefixed ID |
| `kind` | string | `design` / `export` / `remix` / `brand_kit_extract` — discriminator for `input` / `result` shape |
| `status` | string | `queued` / `running` / `succeeded` / `failed` / `canceled` / `expired` |
| `created_at` | ISO 8601 | When the task was created |
| `started_at` | ISO 8601 / null | When the worker picked it up |
| `completed_at` | ISO 8601 / null | Terminal timestamp |
| `progress` | object / null | `{percent, step, message}` — populated during `running` |
| `attempt` | integer | Current attempt number |
| `max_attempts` | integer | Usually 3 — auto-retry cap for transient failures |
| `input` | object | Varies by `kind` (design: `{prompt, format, ...}`; export: `{canvas_id, format, ...}`) |
| `result` | object / null | Populated on `succeeded`; varies by `kind` (design: `{canvas_id, canvas_url, conversation_id, export}`) |
| `error` | object / null | `{message, retryable}` — populated on `failed` |
| `credits` | object / null | `{credits_used, credits_remaining}` on `succeeded` |
| `links` | object | HATEOAS-style relations: `self`, `events`, `cancel`, `canvas` |
| `retry_after_ms` | integer / null | Non-null while non-terminal; typically `3000` (3s) |

## Status state machine

```
queued   → running → succeeded
                   → failed
                   → canceled
                   → expired (rare; long-queued tasks time out)
```

Terminal: `succeeded`, `failed`, `canceled`, `expired`. Non-terminal: `queued`, `running`.

Derive `is_terminal` = `status in {"succeeded","failed","canceled","expired"}`. Derive `can_export` = `status == "succeeded" && result && result.canvas_id`.

## Discriminator — `kind`

Task shape is polymorphic on `kind`:

| `kind` | `input` includes | `result` includes (on succeeded) |
| --- | --- | --- |
| `design` | `prompt`, `format`, `attachments`, `brand_kit_id`, `number_of_slides`, ... | `canvas_id`, `canvas_url`, `conversation_id`, `export` |
| `remix` | `canvas_id`, `prompt`, `brand_kit_id`, ... | `canvas_id`, `canvas_url`, `source_canvas_id` |
| `export` | `canvas_id`, `format`, ... | `export_url`, `format`, `expires_at` |
| `brand_kit_extract` | `url` | `brand_kit_id` |

Always check `kind` before reading `result` fields.

On a succeeded `design` task, `result.export` carries the finished design **already rendered to a file** — `{url, format, status, page_count}`, exported in the canvas's category-default format. Read it directly instead of issuing a separate `POST /v1/canvases/{id}/export`. It is absent when auto-export was disabled (`export_on_complete: {enabled: false}`) or did not finish within the budget.

Note: `POST /v1/canvases/{id}/export` today is **synchronous** — it returns a plain `{url, format}` payload, not a Task envelope. The `export` kind applies to webhook events (`export.succeeded` / `export.failed`) and to long-running export flows if/when they exist. See [`canvases-and-exports.md`](./canvases-and-exports.md).

## Delivery patterns

Pick one per task — don't stack:

### 1. Webhook (`callback_url`) — recommended for async backends

Pass `callback_url` in the task body. Webhook fires on terminal state only. Requires `moda_live_…` API key auth (OAuth callers get `400`). See [`webhooks.md`](./webhooks.md).

### 2. Polling — simplest for short-lived callers

```
POST /v1/tasks → task envelope with retry_after_ms
loop:
  wait retry_after_ms
  GET /v1/tasks/{id}
  break when status is terminal
```

Respect `retry_after_ms`. Don't poll faster.

### 3. `Prefer: wait=<seconds>` — for fast operations only

Add the header on any POST that returns a Task envelope. The server holds the response until terminal OR the wait budget expires.

```
POST /v1/tasks
Prefer: wait=30
```

**Cap: 30 seconds** (server-enforced, per RFC 7240 wait parameter). Valid use cases:

- **Brand-kit creation** (`POST /v1/brand-kits`) — takes 10–30s
- **Remix without a prompt** — synchronous on the backend
- **Short design tasks** with `model_tier: "lite"` and a tight scope

**Not valid for from-scratch design tasks.** They take 2–10 minutes; `wait=30` will time out and return the non-terminal envelope. Use webhooks or polling for design.

**Gateway / proxy warning:** behind a 30s-timeout CDN or load balancer, don't set `wait=30` — you'll hit the gateway timeout before the server times out, and the client sees an abrupt disconnect rather than the graceful envelope return. Use `wait=20` or poll.

### How `Prefer: wait` responds

- If the task reaches terminal inside the budget: returns terminal envelope.
- If the budget expires first: returns the current (non-terminal) envelope. Not an error.

You still need to branch on `status` — the wait header doesn't change the return contract, only the latency.

## Timing expectations

| Operation | Typical time |
| --- | --- |
| `POST /v1/tasks` (design from scratch) | 2–10 min |
| `POST /v1/tasks` with `conversation_id` (follow-up edit) | 1–5 min |
| `POST /v1/remix` **with** a prompt | 2–10 min (it's a design task under the hood) |
| `POST /v1/remix` **without** a prompt (plain duplicate) | < 1s (synchronous, no task) |
| `POST /v1/brand-kits` (from URL) | 10–30s |
| `POST /v1/canvases/{id}/export` | seconds (synchronous signed URL) |

Set user expectations up front. Don't block callers on multi-minute operations.

## Common wrong guesses

- **Using `Prefer: wait=30` on a design task from scratch.** It almost always times out. Use webhooks or polling.
- **Polling faster than `retry_after_ms`.** Burns your rate budget for no latency benefit.
- **Reading `response.canvas_id` on a canonical response.** It's `response.result.canvas_id`. The flat field is legacy (`2026-04-12`).
- **Expecting `export` kind from `POST /v1/canvases/{id}/export`.** That endpoint is synchronous and does not return a Task envelope.
- **Treating `expired` as a failure.** It is terminal (same as the others) but the cause is queue-depth or worker-starvation, not a user-actionable error — retry the task fresh.

## Upstream

- [`docs.moda.app/api/tasks/startTask`](https://docs.moda.app/api/tasks/startTask)
- [`docs.moda.app/api/tasks/getTask`](https://docs.moda.app/api/tasks/getTask)
- [`docs.moda.app/api/versioning`](https://docs.moda.app/api/versioning) — for the legacy → canonical migration map
