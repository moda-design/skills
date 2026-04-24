# Task lifecycle

`start_design_task` and `remix_design` (with a prompt) both kick off asynchronous agent jobs. This reference covers the start → poll → export loop, timing expectations, and failure modes.

## Timing reality

**From-scratch design tasks typically take 2–10 minutes.** A `lite`-tier simple prompt might finish in under a minute; a `pro`-tier multi-page pitch deck can run closer to the upper end. Set expectations with the user explicitly:

> "This usually takes 2–10 minutes. I'll update you when it finishes."

Don't sit silent while polling. Post a brief progress update if a task has been running for more than a minute or two.

## The loop

```
task = start_design_task(prompt="…", format_category="slides", number_of_slides=10)
# {task_id, canvas_id, canvas_url, conversation_id, status: "queued", retry_after_seconds: 3, ...}

status = get_task_status(task_id=task["task_id"])
while not status["is_terminal"]:
    sleep(status["retry_after_seconds"])          # server's cadence hint (~3s)
    status = get_task_status(task_id=task["task_id"])

if status["status"] == "completed" and status["can_export"]:
    export_canvas(canvas_id=status["canvas_id"], format="pptx")
```

### What the status fields mean

| Field | Meaning |
| --- | --- |
| `status` | `queued` → `running` → `completed` / `failed` / `cancelled` |
| `progress_percent` | Estimated progress (0–100). May be `null` early. |
| `current_step` | Short description of what the agent is doing right now. Useful for progress messages. |
| `operations_streamed` | Number of canvas operations applied so far. |
| `is_terminal` | `true` once the task is done (success, failure, or cancellation). Stop polling. |
| `can_export` | `true` only when the task completed successfully and the canvas is exportable. |
| `retry_after_seconds` | Server's suggested delay before the next `get_task_status` call. Typically ~3s. |
| `error` | Human-readable error message on failure; otherwise `null`. |

### Terminal transitions

- `completed` + `can_export: true` → success. Share `canvas_url`; offer `export_canvas`.
- `completed` + `can_export: false` → rare (task finished but canvas data is incomplete). Treat as a soft failure; tell the user and offer to retry.
- `failed` → check `error`. Don't silently retry — failures are usually deterministic (bad input, credit exhaustion, upstream model error).
- `cancelled` → someone cancelled the task via the app UI. Acknowledge and offer to start fresh.

## Polling cadence

Respect `retry_after_seconds`. It's a hint from the server — following it avoids hammering the task-status endpoint and wasting your own rate budget. The default is ~3s, but it can move based on task progress.

Don't poll faster than the hint. Don't hard-code a cadence in your own code.

## Resuming a conversation

Every `start_design_task` / `get_task_status` response includes `conversation_id`. Pass it back on the next `start_design_task` call to resume with full context:

```
# first turn — no conversation_id
task_a = start_design_task(prompt="Create a 10-slide pitch deck for FocusTime…", format_category="slides")
# → conversation_id: "conv_01HT9…"

# later — user says "make the headline bigger"
task_b = start_design_task(
  prompt="Make the headline on slide 1 bigger",
  conversation_id=task_a["conversation_id"],
)
# canvas_id is automatically the conversation's canvas — passing it explicitly is ignored
```

When resuming, the `canvas_id` parameter is **ignored** — the agent already knows which canvas it's editing.

## The not-ready export state

`export_canvas` returns a structured `not_ready` payload (not an error) when a design task is still running on the target canvas:

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

`canvas_id`, `canvas_url`, and `task_id` are only present for authenticated private-canvas exports. Share-link exports omit these.

`reason` is `active_design_job` (wait for the in-flight task) or `task_status_unavailable` (transient lookup failure). Both are retryable — wait `retry_after_seconds` and retry. Don't surface as errors.

## Cancellation

Tasks are cancelled from the Moda app UI, not via MCP. If `get_task_status` returns `cancelled`, treat it like any terminal state — tell the user, offer to start fresh. `can_export` stays false on cancelled tasks.

## Failure modes

| `error` message pattern | Meaning | Action |
| --- | --- | --- |
| Credit / billing errors | Team is out of design credits | Surface to user; suggest upgrading in Moda settings |
| Rate / concurrency errors | Too many concurrent tasks for this team | Wait and retry, or queue sequentially |
| Upstream model errors | Transient | Retry the same prompt after a short delay |
| Validation errors | The prompt or parameters are malformed | Fix the request; don't retry blindly |

## Common wrong guesses

- **Promising synchronous completion ("give me a sec…")** on a 5-minute design task. Tell the user up front that it takes 2–10 minutes.
- **Polling faster than `retry_after_seconds`** — this hammers the server and wastes your rate budget.
- **Retrying a `failed` task with the same prompt** — failures are usually deterministic.
- **Treating `not_ready` from `export_canvas` as an error** — it's a normal retry state.
- **Passing a fresh `canvas_id` when resuming via `conversation_id`** — ignored. The agent uses the conversation's canvas.
- **Calling `export_canvas` without checking `can_export`** — you'll get a `not_ready` response for an in-flight task. Save the roundtrip by gating on `can_export`.

## Upstream

- [`docs.moda.app/mcp/tools#start_design_task`](https://docs.moda.app/mcp/tools#start_design_task)
- [`docs.moda.app/mcp/tools#get_task_status`](https://docs.moda.app/mcp/tools#get_task_status)
- [`docs.moda.app/mcp/tools#export_canvas`](https://docs.moda.app/mcp/tools#export_canvas)
