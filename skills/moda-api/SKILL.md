---
name: moda-api
description: Use Moda's public REST API at api.moda.app. Use when building scheduled jobs, CI pipelines, server-side integrations, webhook receivers, or any Moda automation that runs without a human in the loop and authenticates with a moda_live_ API key. Covers the canonical Task envelope, Moda-Version pinning, prefixed IDs, typed errors with request_id, idempotency_key, cursor pagination, Prefer:wait sync-feel, webhook HMAC verification, the 2-10 minute design task lifecycle, and the synchronous export endpoint.
---

# moda-api

Moda's public REST API at `https://api.moda.app/v1` is the right surface when there is **no human in the loop** — scheduled jobs, CI pipelines, webhook-driven workers, server-side integrations, custom dashboards. Authentication is Bearer token with a `moda_live_…` API key.

If a user is chatting with an AI agent (Claude Desktop, Cursor, etc.), use the [`moda-mcp`](../moda-mcp/SKILL.md) skill instead — it handles OAuth, session context, and chat-shaped flows. The REST API and MCP can both run against the same Moda account.

## Prerequisites

- **Base URL:** `https://api.moda.app/v1`
- **Auth:** `Authorization: Bearer moda_live_<suffix>`. Create keys in **Settings → Developer → REST API**. Keys are shown once; store in a secret manager. See [`references/authentication.md`](./references/authentication.md) for the 13 scopes.
- **Version:** pin `Moda-Version: 2026-05-01` on every request. Omitting it resolves to the current default (`2026-04-12` today, advancing on sunset dates). See [`references/versioning.md`](./references/versioning.md).

Every write in this skill's examples uses `Moda-Version: 2026-05-01`. Every body JSON uses prefixed IDs (`cvs_…`, `task_…`, `bk_…`, `file_…`).

## Before you call `POST /v1/tasks` — HARD GATE

Design tasks take **2–10 minutes**. Getting the input right up front saves a lot of wasted compute and retry cycles. Run this pre-flight checklist before every task start:

1. **Format.** Set `format_category` explicitly for anything other than slides (`slides` / `social` / `carousel` / `pdf` / `diagram` / `ui` / `other`). Omitting it produces a slide deck regardless of intent. See [`references/canvases-and-exports.md`](./references/canvases-and-exports.md) and [`references/task-envelope.md`](./references/task-envelope.md) for allowed values and dimensions.
2. **Brand.** Fetch `GET /v1/brand-kits` and pick `brand_kit_id`. The team default auto-applies when omitted. Set `skip_brand_kit: true` to opt out explicitly.
3. **References.** If the task needs a source doc or style reference, `POST /v1/uploads` first, then pass `attachments: [{file_id, role}]` on the task. For an existing canvas as inspiration, use `reference_canvas_ids`.
4. **Idempotency.** For retry-safe scheduled jobs, pass an `idempotency_key` derived from a stable key (e.g. `"weekly-deck:2026-W17"`). Repeat calls with the same key return the same task, not a duplicate. See [`references/idempotency.md`](./references/idempotency.md).
5. **Delivery strategy.** Choose one up front:
   - **Webhook** (`callback_url`) — fires once on terminal state; best for cron / backend workers. API-key auth only (OAuth callers get `400`).
   - **Poll** `GET /v1/tasks/{id}` at the `retry_after_ms` cadence (~3s) — best when the caller is short-lived.
   - **`Prefer: wait=<s>`** (max 30s) — best for **fast** operations (brand-kit creation, remix-without-prompt). Design tasks almost always exceed 30s; `wait` will time out and return the non-terminal envelope. See [`references/task-envelope.md#prefer-wait`](./references/task-envelope.md).
6. **IDs.** Every ID in a JSON body must be prefixed (`cvs_…`, `task_…`, `bk_…`, `file_…`, `conv_…`). Path parameters tolerate bare UUIDs for convenience. Sending a bare UUID in a body returns `400 invalid_request`. See [`references/ids.md`](./references/ids.md).

## The canonical flow

```
(1) create API key + pick scopes      → Settings → Developer → REST API
(2) ensure a brand kit                 → GET /v1/brand-kits (create if missing)
(3) upload references (if any)         → POST /v1/uploads or POST /v1/uploads/from-url
(4) start the design task              → POST /v1/tasks with format_category + callback_url or Prefer: wait
(5) receive terminal state             → webhook (task.succeeded / failed / canceled) OR GET /v1/tasks/{id} poll
(6) export the canvas                  → POST /v1/canvases/{id}/export (synchronous; returns signed URL)
```

### Minimum viable example

**TypeScript (Node 20+, `fetch`)**:

```ts
const HEADERS = {
  Authorization: `Bearer ${process.env.MODA_API_KEY!}`,
  "Moda-Version": "2026-05-01",
  "Content-Type": "application/json",
};

// 4. start the task
const taskRes = await fetch("https://api.moda.app/v1/tasks", {
  method: "POST",
  headers: HEADERS,
  body: JSON.stringify({
    prompt: "Create a 10-slide pitch deck for FocusTime...",
    format: { category: "slides", width: 1920, height: 1080 },
    number_of_slides: 10,
    callback_url: "https://your-server.com/webhooks/moda",
    idempotency_key: "focustime-v1",
  }),
});
const task = await taskRes.json();
// { id: "task_01HT9...", kind: "design", status: "queued", retry_after_ms: 3000, ... }

// 5a. poll (alternative to webhook)
let status = task;
while (!["succeeded", "failed", "canceled", "expired"].includes(status.status)) {
  await new Promise(r => setTimeout(r, status.retry_after_ms ?? 3000));
  status = await fetch(`https://api.moda.app/v1/tasks/${task.id}`, { headers: HEADERS }).then(r => r.json());
}

// 6. export
if (status.status === "succeeded") {
  const exportRes = await fetch(
    `https://api.moda.app/v1/canvases/${status.result.canvas_id}/export?format=pptx`,
    { method: "POST", headers: HEADERS },
  );
  const { url } = await exportRes.json();
}
```

**Python (3.11+, `httpx`)**:

```python
import os, time, httpx

HEADERS = {
    "Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
    "Moda-Version": "2026-05-01",
}

with httpx.Client(base_url="https://api.moda.app/v1", headers=HEADERS, timeout=30) as c:
    # 4. start
    task = c.post("/tasks", json={
        "prompt": "Create a 10-slide pitch deck for FocusTime...",
        "format": {"category": "slides", "width": 1920, "height": 1080},
        "number_of_slides": 10,
        "callback_url": "https://your-server.com/webhooks/moda",
        "idempotency_key": "focustime-v1",
    }).json()

    # 5. poll
    while task["status"] not in {"succeeded", "failed", "canceled", "expired"}:
        time.sleep((task.get("retry_after_ms") or 3000) / 1000)
        task = c.get(f"/tasks/{task['id']}").json()

    # 6. export
    if task["status"] == "succeeded":
        exp = c.post(f"/canvases/{task['result']['canvas_id']}/export",
                     params={"format": "pptx"}).json()
```

## Core concepts

- **13 scopes, minimum-privilege principle.** Pick only what the integration needs. `tasks:write` lets you start design tasks; `designs:export` lets you export; `brand_kits:write` lets you create kits. Full list: [`references/authentication.md`](./references/authentication.md).

- **`Moda-Version: 2026-05-01` is canonical.** Pin explicitly on every request. Unpinned traffic resolves to the current default and changes shape when the default advances on sunset dates. [`references/versioning.md`](./references/versioning.md).

- **Task envelope.** Every task-shaped operation (design, export task, remix, brand_kit_extract) returns `{id, kind, status, result, error, progress, input, credits, links, retry_after_ms}`. Branch your code on `status` (`queued` / `running` / `succeeded` / `failed` / `canceled` / `expired`). [`references/task-envelope.md`](./references/task-envelope.md).

- **Prefixed IDs.** Response `id` fields always come back prefixed (`cvs_01HT9…`, `task_01HT9…`, `bk_01HT9…`, `file_01HT9…`, `conv_01HT9…`, `evt_01HT9…`, `org_…`, `team_…`). Request body fields require prefixed form — bare UUIDs get `400 invalid_request`. Path parameters tolerate bare UUIDs as a convenience. [`references/ids.md`](./references/ids.md).

- **Typed error envelope.** `{error: {type, code, message, doc_url, request_id, details?, retry_after_ms?, causes?}}`. Branch on `type`, not HTTP status code. Log `request_id` on every error. Retry `upstream_error` and `rate_limited`; fix everything else. [`references/errors.md`](./references/errors.md).

- **Cursor pagination.** List endpoints return `{data: [...], next_cursor}`. Iterate until `next_cursor === null`. Cursors are opaque + signed — don't hand-craft. Sort is `(created_at DESC, id DESC)` on immutable columns. [`references/pagination.md`](./references/pagination.md).

- **`idempotency_key` on `POST /v1/tasks`.** Retry-safe across network timeouts and worker restarts. Reusing the same key returns the existing task, not a duplicate. [`references/idempotency.md`](./references/idempotency.md).

- **`callback_url` is API-key-auth only.** OAuth callers get `400 "callback_url is only supported for API-key authenticated callers"`. Use polling from OAuth clients. Webhooks fire terminal-only (`task.succeeded` / `task.failed` / `task.canceled` / `export.succeeded` / `export.failed`) — sign verification is HMAC-SHA256 over `{timestamp}.{body}`. [`references/webhooks.md`](./references/webhooks.md).

## Common tasks

| Job-to-be-done | Recipe |
| --- | --- |
| Weekly cron: generate a status deck, post URL to Slack | [`recipes/scheduled-generation.md`](./recipes/scheduled-generation.md) |
| CSV of 50 prospects → 50 personalized decks | [`recipes/bulk-personalization.md`](./recipes/bulk-personalization.md) |
| Export every team canvas as PDF to S3/Drive | [`recipes/export-pipeline.md`](./recipes/export-pipeline.md) |
| Receive + verify + process webhooks | [`recipes/webhook-receiver.md`](./recipes/webhook-receiver.md) |
| Upload a brief PDF → branded deck → PPTX | [`recipes/brief-to-deck-pdf-intake.md`](./recipes/brief-to-deck-pdf-intake.md) |
| GitHub Action: regenerate theme tokens from a canonical canvas | [`recipes/design-to-code-ci.md`](./recipes/design-to-code-ci.md) |

## Errors & retries — quick table

| `error.type` | Retry? | Action |
| --- | --- | --- |
| `invalid_request` | No | Fix the request (missing / malformed field) |
| `authentication` | No | Check the API key |
| `permission` | No | Add the missing scope, or access a resource the key's team owns |
| `not_found` | No | Check the ID; confirm team access |
| `conflict` | No | Resolve state conflict (usually a name collision) |
| `idempotency_conflict` | No | Reusing an idempotency_key with a different body — fix the key or the body |
| `rate_limited` | Yes | Respect `Retry-After` (seconds) |
| `upstream_error` | Yes | Transient upstream failure — back off and retry |
| `internal_error` | Yes | Server error — retry with backoff; include `request_id` when reporting |
| `unprocessable` | No | Validation failed on well-formed input |

Full catalog + code examples: [`references/errors.md`](./references/errors.md).

## Further reading

- [`docs.moda.app/api`](https://docs.moda.app/api) — overview
- [`docs.moda.app/api/authentication`](https://docs.moda.app/api/authentication) — keys + scopes
- [`docs.moda.app/api/versioning`](https://docs.moda.app/api/versioning) — Moda-Version header, migration map
- [`docs.moda.app/api/webhooks`](https://docs.moda.app/api/webhooks) — webhook payload + signing
- [`docs.moda.app/api/tasks/startTask`](https://docs.moda.app/api/tasks/startTask) — full per-field reference
- [`docs.moda.app/llms.txt`](https://docs.moda.app/llms.txt) / [`docs.moda.app/llms-full.txt`](https://docs.moda.app/llms-full.txt) — plain-text for LLMs
