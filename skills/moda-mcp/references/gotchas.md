# Gotchas

The MCP surface has several behaviors that won't show up in tool signatures. This page is the one-stop reference for the silent-fail / surprising-behavior set.

## Format and dimensions

**`format_category` silently defaults to slides** on `start_design_task` if omitted. Always set it explicitly:

| User wants | `format_category` | Also pass |
| --- | --- | --- |
| Pitch deck, presentation | `slides` | typical `format_width=1920`, `format_height=1080` |
| Single Instagram / LinkedIn / Twitter / banner | `social` | platform-specific `format_width`/`format_height` |
| Instagram or LinkedIn **carousel** post | `carousel` | `carousel_dimensions` (`square`/`linkedin`/`portrait`) + `carousel_page_count` (1–5) |
| PDF report, resume, one-pager | `pdf` | |
| Flowchart, org chart, process diagram | `diagram` | |
| UI mockup, screen, wireframe | `ui` | `format_width`/`format_height` |
| Poster, infographic, anything else | `other` | `format_width`/`format_height` |

**Slide count goes in the prompt text**, not a parameter. Say "10-slide deck" in the prompt. The REST API has `number_of_slides`; the MCP server does not expose it.

**Carousel cap = 5 panels.** "10 IG carousel slides" violates the cap. Push back: offer 5 carousel panels (Pattern C of the bulk recipe) or 10 standalone social posts (Pattern A).

**`model_tier="pro_max"`** is silently coerced to `pro`. Pass `pro` directly.

## Task lifecycle

**`start_design_task` defaults to `wait=False`** — returns a task handle (`task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status: "queued"`) in milliseconds. Poll `get_task_status(task_id)` at `retry_after_seconds` (~3s) until `is_terminal == true`. Call `export_canvas` only when `can_export == true`.

**`remix_design` defaults to `wait=True`** — opposite of `start_design_task`. With a prompt, it blocks until the agent finishes. For bulk fan-out, **pass `wait=False` explicitly** or each call serializes.

**Terminal statuses**: `completed`, `failed`, `cancelled`, `dead_letter`. Stop polling on any.

**Cancellation**: `cancel_task(task_id)`. No-op on already-terminal tasks. Cancelling a blocking MCP call publishes the cancel signal internally — billing stops with the job.

**Failed tasks are deterministic**. Don't silently retry on `{status: "failed"}` — surface the `error` to the user. The exception is upstream model errors, which are sometimes transient (retry once).

## Conversations vs canvases vs remixes

| User intent | Use |
| --- | --- |
| Iterate on the same design ("make the headline bigger") | `start_design_task(prompt=…, conversation_id=…)` — agent has full prior context |
| Edit an existing canvas in place ("add a footer to my deck") | `start_design_task(prompt=…, canvas_id=…)` — destructive, modifies the canvas |
| Fork a canvas with variations, especially across brand kits ("make a version of this for each client") | `start_design_task(prompt=…, template_canvas_id=…, brand_kit_id=…)` — duplicates first; server auto-picks content-only remix vs full rebrand from brand-kit comparison; original preserved |
| Plain sync duplicate, no prompt | `remix_design(canvas_id=…)` — single synchronous call, returns the new canvas |

**Mutual-exclusion matrix on `start_design_task`:**

| Combo | Behavior |
| --- | --- |
| `canvas_id` + `template_canvas_id` | Tool error |
| `template_canvas_id` + `conversation_id` | Tool error |
| `canvas_id` + `conversation_id` | No error — `canvas_id` is silently ignored; the agent uses the conversation's canvas |

The asymmetry is intentional: `conversation_id` always wins over `canvas_id` (older quirk, predates `template_canvas_id`), but `template_canvas_id` is strict because it changes the operation shape (source-copy-then-run vs in-place edit / resume).

## Brand kits

**`find_brand_kits` for lookups; `list_brand_kits` only when the user asked to see them.** Both return the same data, but `list_brand_kits` renders a visual showcase iframe on **every** call (per the MCP Apps spec, iframe rendering is decided at tool-listing time and can't be suppressed per-call). When you're just trying to pick a `brand_kit_id` for another tool, use `find_brand_kits` — it's JSON-only and doesn't steal screen real estate.

**Resolution order for `start_design_task` / `remix_design`:**
1. Explicit `brand_kit_id` parameter (highest priority)
2. Session preference (`set_session_brand_kit`, or the showcase iframe's "Use for this session" button)
3. Team default brand kit
4. None (only when `skip_brand_kit=true` is set)

**Don't restate brand colors / fonts / logos in the prompt** when a kit applies — it fights the kit.

**`set_context` clears the session brand kit.** Kits are team-scoped; a kit pinned on Team A is meaningless on Team B.

**`set_session_brand_kit` is session-only.** It does NOT touch the team default. To change the team default, use `set_default_brand_kit` — destructive, only call on explicit user request.

**Ask the user when the team has multiple kits** and `whoami` shows no session preference. Silently falling back to the default isn't always what they want.

**First kit per team becomes default automatically.** To promote a different kit later as the *team* default, use `set_default_brand_kit(brand_kit_id)`.

## Attachments

**Two shapes:**
- File-id form (preferred): `{file_id, role, label?}` — carries `role` that changes agent behavior
- URL form (legacy, public URLs only): `{url, name?, type?}` — drops role metadata

**Roles change behavior:**
- `source` — extract content from this file (use its text/data — e.g. a brief PDF, meeting notes)
- `reference` — emulate this file's style (don't copy content — e.g. a screenshot of a design you like)
- `asset` — drop the file in verbatim (e.g. a logo, hero image)

Passing a logo as `reference` makes the agent emulate its style instead of placing it. Passing a brief as `reference` makes the agent mimic its formatting instead of using its content.

**Don't confuse this with the brand-kit-image role enum.** `add_brand_kit_image(role=…)` uses a different (overlapping but distinct) set: `logo` / `reference` / `asset`. `logo` belongs to brand-kit images only; `source` belongs to design-task attachments only.

**Two upload paths:**
- `upload_file(source_url=…)` — one call, when the file is already at a public URL. Content-hash deduplicated.
- `create_upload_url` → PUT bytes to the returned `upload_url` → `register_uploaded_file(storage_key, …)` — three steps, when the file is local with no public URL.

**The `create_upload_url` PUT goes to `mcp.moda.app`.** The `upload_url` it returns is on the Moda MCP host itself (`https://mcp.moda.app/uploads/proxy?token=…`) — not a Google Cloud Storage URL. That's deliberate: it's the same host the MCP connector already talks to, so sandboxed clients with a network egress allow-list don't need a separate rule. If a hardened client *does* block the out-of-band PUT, the one host to allow is `mcp.moda.app` — never all of `storage.googleapis.com`.

For existing Moda canvases as inspiration, don't upload a screenshot — pass `reference_canvas_ids=[cvs_…]` directly. The agent sees the structure natively.

## Concurrency caps (bulk fan-out)

Per-team in-flight cap on `start_design_task` + `remix_design`:

| Plan | Max concurrent tasks |
| --- | --- |
| `free` / `free_beta` | 3 |
| `paid` | 10 |
| `ultra` / `enterprise` | 15 |

Exceeding the cap surfaces as a tool error on the call that puts you over. Use a windowed launch — keep at most `cap` tasks in flight; slot in the next as each terminates. Default the window to 3 when the plan is unknown. See [`../recipes/bulk-variants.md`](../recipes/bulk-variants.md) for the pattern.

## Exports

**A finished design task already includes its export — don't re-export.** A completed `start_design_task` / `remix_design` carries `result.export` (`{url, format, status, page_count}`) — the design rendered to a file in the canvas's category-default format. Read that. Calling `export_canvas` for the same just-finished canvas re-does work the task already did; only call it for a *different* format or page, or for a canvas that wasn't just produced by a task.

**`export_canvas` returns `{status: "not_ready", reason, retry_after_seconds}`** while a design task is still running on the canvas. **Not an error** — retry after `retry_after_seconds`. Reasons: `active_design_job` (most common), `task_status_unavailable` (transient).

**Large multi-page PDFs/PPTX** can exceed the ~20s sync wait budget and return `{status: "in_progress", task_id}`. Poll `get_export_status(task_id)` for the URL. Export task records are kept ~1 hour.

**Signed export URLs expire after 7 days.**

**Image vs document defaults**: PNG / JPEG default to page 1 (use `page_number` for others). PDF / PPTX default to all pages.

## Session context (multi-org users)

Session context (org + team) is sticky for 24h across reconnections.

- Single-org user: nothing to do; primary workspace applies.
- Multi-org user: call `get_context()` at session start; if unset, ask which org/team. `set_context(org_name, team_name)` takes **names** (case-insensitive), not UUIDs.

All workspace-scoped tools (`list_brand_kits`, `start_design_task`, `remix_design`, `upload_file`) read from session context. Per-call overrides: pass `org_id` / `team_id` for one-call overrides without changing the session default.

## Design-to-code (separate workflow)

`get_moda_canvas(url=…)` returns semantic pseudo-HTML (`<Card>`, `<Button>`, `<Heading>`, etc.) that maps directly to React / Vue / HTML / SwiftUI. `get_moda_canvas_tokens(url=…)` returns colors / fonts / radii / variables as JSON for theme config.

- **Layer names drive tag quality.** A rectangle named `cta-button` becomes `<Button>`. Unnamed elements use visual heuristics.
- **Multi-page canvases**: call `list_moda_canvas_pages(url=…)` first to plan per-page fetches; omitting `page_number` concatenates everything into one (expensive) response.
- **Pair with `export_canvas(format="png")`** for pixel-perfect or complex-gradient cases that pseudo-HTML can't fully capture.

Full guides: [`docs.moda.app/mcp/design-to-code`](https://docs.moda.app/mcp/design-to-code) and [`docs.moda.app/mcp/naming-layers`](https://docs.moda.app/mcp/naming-layers).
