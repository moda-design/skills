# Errors and retries

Moda MCP has three failure modes to distinguish: **structured not-ready states** (retryable, normal), **task failures** (deterministic, surface to user), and **tool / auth errors** (fix and retry, or escalate).

## Structured `not_ready` — retryable, normal

`export_canvas` returns this when a design task is still running on the target canvas:

```json
{
  "status": "not_ready",
  "reason": "active_design_job",
  "retry_after_seconds": 3,
  "canvas_id": "550e8400-…",
  "canvas_url": "https://moda.app/canvas/…",
  "task_id": "990e8400-…"
}
```

**Do not surface this as an error.** Wait `retry_after_seconds` and retry `export_canvas`. If you already have the `task_id`, you can also poll `get_task_status` to decide when to retry.

Reasons:

| `reason` | Meaning | Retry |
| --- | --- | --- |
| `active_design_job` | A design task is currently running on this canvas | Yes — wait `retry_after_seconds` and retry |
| `task_status_unavailable` | Transient lookup failure | Yes — wait `retry_after_seconds` and retry |

`canvas_id`, `canvas_url`, `task_id` are only present for authenticated private-canvas exports. Share-link exports omit them to avoid leaking internal IDs.

## Task failures — deterministic, surface to user

`get_task_status` returns `{status: "failed", error: "…", ...}` when the design agent couldn't complete the task:

| `error` pattern | Likely cause | Action |
| --- | --- | --- |
| Credit / billing related | Team out of design credits | Surface. Suggest upgrading or switching to a team with credits. |
| Concurrency / rate | Too many concurrent tasks for this team | Retry after a brief delay. Queue sequentially if recurring. |
| Upstream model error | Transient model-provider failure | Retry **once**; escalate if it fails again with the same symptom. |
| Validation / bad input | The prompt + parameters couldn't be parsed | Fix the request. Don't retry blindly. |
| Canvas not found / not editable | Bad `canvas_id` or permissions | Check the ID; confirm the user has access to the target canvas. |

**Do not silently retry on `failed`** unless the symptom is specifically transient (upstream model error). Failures are usually deterministic — retrying the same prompt produces the same failure.

Tell the user what failed in a single sentence, then offer a concrete next step ("your team is out of credits — upgrade in Moda settings, or I can draft the prompt so you can run it later").

## Task cancellation

`get_task_status` returns `{status: "cancelled"}` when a task was cancelled — either from the Moda app UI or via `cancel_task(task_id)`. `can_export` stays `false`. Treat it like any other terminal state: acknowledge to the user, offer to start fresh.

`cancel_task(task_id)` is a no-op on already-terminal tasks. Cancelling an MCP tool call while `start_design_task` / `remix_design` are blocking (`wait=True`) also publishes the cancel internally — billing stops with the job.

## Auth / connection errors

| Symptom | Cause | Fix |
| --- | --- | --- |
| Tool call returns a 401-style error | OAuth session expired, or API key revoked / invalid | Ask the user to re-authenticate (per-client instructions below) |
| Tool call returns a 403-style error | Insufficient scope (API key) or insufficient workspace permissions | Check the key's scopes or the user's role in the team |
| Specific tool "not available when using the local stdio server" | Tool requires the remote `mcp.moda.app/mcp` server | Switch to the remote server |
| `get_moda_canvas` on a `moda.app/canvas/…` URL fails | Private canvas + unauthenticated caller | Authenticate (share link if unavailable) |

Re-auth per client:

- **Claude Desktop / claude.ai**: **Settings → Connectors** → disconnect, reconnect.
- **Claude Code**: `claude mcp remove moda`; `claude mcp add --transport http moda https://mcp.moda.app/mcp`; `claude /mcp` → authenticate.
- **Cursor**: **Settings → MCP** → restart the server.
- **VS Code**: Restart the extension or the app.

## Rate and concurrency

The server enforces per-endpoint rate limits. They surface as task-status `error` messages when hit; the immediate tool call (like `start_design_task`) typically returns an error surface (HTTP 429-equivalent in the MCP response) with a suggested delay.

Slow down the cadence or reduce parallelism. Don't hammer.

## Common wrong guesses

- **Treating `{status: "not_ready"}` as an error and surfacing it to the user.** It's a retryable state, not a failure.
- **Silently retrying `failed` tasks.** Failures are deterministic — same input, same failure.
- **Retrying `cancelled` tasks without asking the user.** Someone cancelled on purpose; confirm before re-running.
- **Hammering `get_task_status` faster than `retry_after_seconds`.** Costs you rate budget.
- **Asking the user to re-authenticate on every transient network error.** 401 only; others are transient.

## Upstream

- [`docs.moda.app/mcp/tools#export_canvas`](https://docs.moda.app/mcp/tools#export_canvas) — `not_ready` payload details
- [`docs.moda.app/mcp/tools#get_task_status`](https://docs.moda.app/mcp/tools#get_task_status) — full status / error fields
- [`docs.moda.app/mcp/help`](https://docs.moda.app/mcp/help) — contact support
