# Moda MCP — tools reference

The Moda MCP server exposes 17 public tools. This is a compressed reference — the authoritative catalog lives at [`docs.moda.app/mcp/tools`](https://docs.moda.app/mcp/tools).

## Session

### `set_context`
Set the active organization and team for the session. Persists 24 hours across reconnects.

| Parameter | Type | Required |
| --- | --- | --- |
| `org_name` | string | yes |
| `team_name` | string | no (defaults to org's default team) |

### `get_context`
Show the current session context. No parameters.

### `list_organizations`
List orgs + teams the user belongs to. No parameters. Use names (not IDs) in user-facing messages.

## Canvas read + design-to-code

### `get_moda_canvas`
Fetch a canvas as semantic pseudo-HTML with CSS properties + design tokens. The primary design-to-code tool.

| Parameter | Type | Required |
| --- | --- | --- |
| `url` | string | yes — share URL, private canvas URL, or raw share token |
| `page_number` | integer \| null | no — omit for all pages |

### `get_moda_canvas_tokens`
Return only the design tokens (colors, fonts, variables, radii) as structured JSON. Use when generating theme files without the full layout.

| Parameter | Type | Required |
| --- | --- | --- |
| `url` | string | yes |
| `page_number` | integer \| null | no |

### `list_moda_canvas_pages`
List pages in a multi-page canvas with dimensions + node counts. Call this before `get_moda_canvas` on multi-page designs to plan per-page fetches.

| Parameter | Type | Required |
| --- | --- | --- |
| `url` | string | yes |

### `list_my_canvases`
Paginated list of canvases the user has access to. Ordered by most recently updated.

| Parameter | Type | Default |
| --- | --- | --- |
| `limit` | integer | 20 (max 100) |
| `offset` | integer | 0 |

### `search_canvases`
Search canvases by name / content. Use when the user says "find my deck from March" or "my Q1 social ad."

| Parameter | Type | Default |
| --- | --- | --- |
| `query` | string | — |
| `limit` | integer | 20 (max 100) |

## Brand kits

### `list_brand_kits`
List brand kits for the active team (from session context, or override via `org_id` / `team_id`). Call before `start_design_task` to check for a default.

### `create_brand_kit`
Extract brand data (colors, fonts, logos, tone) from a company website URL. Takes 10–30s. First kit per team becomes the default automatically.

| Parameter | Type | Required |
| --- | --- | --- |
| `url` | string | yes — website URL or bare domain (`stripe.com`) |
| `org_id` / `team_id` | string | no |

### `update_brand_kit`
Partial update. Pass only the fields you want to change. When updating `colors` or `fonts`, the entire array is replaced (not merged).

| Parameter | Type | Required |
| --- | --- | --- |
| `brand_kit_id` | string | yes |
| `title`, `colors`, `fonts`, `company_name`, `company_description`, `tagline`, `brand_values`, `brand_aesthetic`, `brand_tone_of_voice` | various | no |

## Uploads

### `upload_file`
Upload a file from a public URL into Moda's storage. Returns a stable `file_id` + proxy URL for use as an attachment. Content-hash deduplication — uploading the same file twice returns the existing record (`was_duplicate: true`). Supported: PNG, JPEG, WebP, PDF, PPTX.

| Parameter | Type | Required |
| --- | --- | --- |
| `source_url` | string | yes |
| `filename` | string | no (inferred from URL) |

## Design tasks

### `start_design_task`
**Always async.** Creates or edits a canvas based on the prompt. Returns a task handle immediately; poll `get_task_status`.

Key parameters (full list in the docs):

| Parameter | Type | Notes |
| --- | --- | --- |
| `prompt` | string | required. Natural-language design instructions. |
| `canvas_id` | string | omit to create new; provide to edit existing |
| `canvas_name` | string | name for the new canvas (create-only) |
| `brand_kit_id` | string | default team kit is used if omitted |
| `skip_brand_kit` | boolean | opt out of brand styling entirely |
| `conversation_id` | string | resume a prior conversation with full context |
| `attachments` | array | `{file_id, role, label?}` or `{url, name?, type?}` |
| `reference_canvas_ids` | string[] | existing canvases to draw inspiration from |
| `format_category` | string | `slides` \| `social` \| `carousel` \| `pdf` \| `diagram` \| `ui` \| `other` |
| `format_width`, `format_height` | integer | canvas dimensions in pixels |
| `carousel_dimensions` | string | `square` \| `linkedin` \| `portrait` (when `format_category="carousel"`) |
| `carousel_page_count` | integer | capped at 5 (when `format_category="carousel"`) |
| `number_of_slides` | integer | pin slide count |
| `model_tier` | string | `pro` / `standard` / `lite` (auto if omitted) |

Return fields: `task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status`, `retry_after_seconds`.

### `get_task_status`
Poll task progress. Returns `task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status`, `progress_percent`, `current_step`, `is_terminal`, `can_export`, `retry_after_seconds`, `operations_streamed`, `created_at`, `started_at`, `completed_at`, `error`.

Statuses: `queued`, `running`, `completed`, `failed`, `cancelled`. Stop polling when `is_terminal == true`. Call `export_canvas` only when `can_export == true`.

### `list_tasks`
List recent design tasks. Filter by `canvas_id`, `status`, `limit` (max 50).

### `remix_design`
Duplicate a canvas; optionally start a design task on the copy. Original is never modified.

| Parameter | Type | Required |
| --- | --- | --- |
| `canvas_id` | string | yes — canvas to duplicate |
| `prompt` | string | no — omit for plain duplicate (synchronous); include to queue a design task (async, poll the returned `task_id`) |
| `new_name` | string | no — defaults to `"<original> (Remix)"` |
| `brand_kit_id` | string | no — only used when `prompt` is provided |

## Export

### `export_canvas`
Export a canvas as PNG, JPEG, PDF, or PPTX. Pass exactly one of `canvas_id` or `url`.

| Parameter | Type | Default |
| --- | --- | --- |
| `canvas_id` | string | — |
| `url` | string | — |
| `format` | string | `"png"` (one of `png` / `jpeg` / `pdf` / `pptx`) |
| `page_number` | integer \| null | image formats default to page 1; document formats default to all pages |

Returns `{status: "completed", url, format}` on success, or a structured `{status: "not_ready", reason, retry_after_seconds, ...}` when a design task is still active on the canvas. Signed URL expires after 7 days.

## Common wrong guesses

- **Calling `start_design_task` without `format_category`** when the user asked for an Instagram post, carousel, PDF, or anything other than slides. Default is slides; always set the category explicitly.
- **Using `format_category="social"` for an Instagram carousel**. Use `carousel` + `carousel_dimensions` + `carousel_page_count` — `social` produces a single static post.
- **Passing a share URL where a `canvas_id` is expected** (e.g. in `reference_canvas_ids`). Use `list_my_canvases` or `search_canvases` to resolve first.
- **Treating the structured `{status: "not_ready"}` from `export_canvas` as an error**. It's a retryable state.
- **Paste-bombing public URLs into `attachments`** when the user has a local file. Call `upload_file` first and pass `{file_id, role}`.
- **Asking for `list_tasks` with `limit > 50`** — the cap is 50.
- **Forgetting `canvas_id` is ignored when resuming via `conversation_id`** — the agent already knows which canvas to edit.

## Upstream

Canonical catalog with parameter-by-parameter detail and examples: [`docs.moda.app/mcp/tools`](https://docs.moda.app/mcp/tools).
