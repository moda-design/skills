# Moda MCP — tools reference

The Moda MCP server exposes 25+ public tools. This is a compressed reference — the authoritative catalog lives at [`docs.moda.app/mcp/tools`](https://docs.moda.app/mcp/tools).

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
| `limit` | integer | 6 (max 100) |
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

### `set_default_brand_kit`
Mark a brand kit as the team's default. Clears the default flag on whichever kit was previously default. Idempotent. Only call when the user explicitly asks. Single parameter: `brand_kit_id`.

### `delete_brand_kit`
Soft-delete a brand kit. Destructive — only call when the user explicitly names the kit to delete; never as part of a "cleanup" or bulk action the user didn't request.

### `list_brand_kit_images`
List all images attached to a brand kit (logos + references) in newest-first order. Useful before `add_brand_kit_image` to avoid duplicates.

### `add_brand_kit_image`
Attach an uploaded `file_id` to a brand kit with a role. Roles: `"logo"` (used downstream in designs), `"reference"` (style hint to the agent; default if `role` is omitted), `"asset"` (includable in designs). Note: this role enum is **distinct** from the attachment `role` enum used by `start_design_task` (`source` / `reference` / `asset`) — both share `reference` and `asset` but `logo` is brand-kit-only.

### `remove_brand_kit_image`
Detach an image from a brand kit by its `bki_` ID. Underlying file stays in storage; only the kit reference is removed. Destructive — only call on explicit user request.

## Uploads

### `upload_file`
Upload a file from a public URL into Moda's storage. Returns a stable `file_id` + proxy URL for use as an attachment. Content-hash deduplication — uploading the same file twice returns the existing record (`was_duplicate: true`). Supported: PNG, JPEG, WebP, PDF, PPTX.

| Parameter | Type | Required |
| --- | --- | --- |
| `source_url` | string | yes |
| `filename` | string | no (inferred from URL) |

### `create_upload_url`
**Step 1 of the two-step local-file upload.** Returns a signed PUT URL + `storage_key`. PUT the file bytes to that URL out-of-band (e.g. `curl -X PUT --data-binary @file.png -H 'Content-Type: image/png' <url>`), then call `register_uploaded_file`. Use this path when the file is on disk and not already at a public URL.

| Parameter | Type | Required |
| --- | --- | --- |
| `filename` | string | yes |
| `mime_type` | string | no — defaults to `"application/octet-stream"`; match what you PUT |

### `register_uploaded_file`
**Step 2 of the two-step local-file upload.** Call after PUTing bytes to the URL from `create_upload_url`. Returns the same `{id, url, ...}` shape as `upload_file` — pass the `file_id` to `add_brand_kit_image` or `start_design_task` attachments.

| Parameter | Type | Required |
| --- | --- | --- |
| `storage_key` | string | yes — from `create_upload_url` |
| `filename` | string | yes |
| `mime_type` | string | yes (match the Content-Type you PUT) |

## Design tasks

### `start_design_task`
**Always async.** Creates or edits a canvas based on the prompt. Returns a task handle immediately; poll `get_task_status`.

Key parameters (full list in the docs):

| Parameter | Type | Notes |
| --- | --- | --- |
| `prompt` | string | required. Natural-language design instructions. |
| `canvas_id` | string | omit to create new; provide to edit existing. Mutually exclusive with `template_canvas_id`. |
| `template_canvas_id` | string | source canvas to remix into a new canvas. Server copies the source, applies `brand_kit_id` (or team default) on the copy, then runs the agent. Skill is auto-selected: same brand kit as source → content-only remix; different brand kit → full rebrand. Source canvas does not need to be a "template" — any canvas your team can read works. Mutually exclusive with `canvas_id` AND `conversation_id`. |
| `canvas_name` | string | name for the new canvas. Used when creating fresh (no `canvas_id` / `template_canvas_id`) or when remixing via `template_canvas_id` (overrides default `"Remix of <source>"`). |
| `brand_kit_id` | string | default team kit is used if omitted. With `template_canvas_id`, controls whether the agent rebrands the copy (different kit) or just edits content (same kit). |
| `skip_brand_kit` | boolean | opt out of brand styling entirely |
| `conversation_id` | string | resume a prior conversation with full context |
| `attachments` | array | `{file_id, role, label?}` or `{url, name?, type?}` |
| `reference_canvas_ids` | string[] | existing canvases to draw inspiration from |
| `format_category` | string | `slides` \| `social` \| `carousel` \| `pdf` \| `diagram` \| `ui` \| `other` |
| `format_width`, `format_height` | integer | canvas dimensions in pixels |
| `carousel_dimensions` | string | `square` \| `linkedin` \| `portrait` (when `format_category="carousel"`) |
| `carousel_page_count` | integer | capped at 5 (when `format_category="carousel"`) |
| `model_tier` | string | `pro` / `standard` / `lite` (auto if omitted) |
| `wait` | boolean | default `false` — return a task handle immediately, poll with `get_task_status`. Pass `true` to block on completion (rarely useful via MCP). |

Slide count for `slides` decks goes **in the prompt text** ("a 10-slide deck"). There is no `number_of_slides` MCP parameter — the REST API exposes one, but the MCP server does not.

Return fields: `task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status`, `retry_after_seconds`.

### `get_task_status`
Poll task progress. Returns `task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status`, `progress_percent`, `current_step`, `is_terminal`, `can_export`, `retry_after_seconds`, `operations_streamed`, `created_at`, `started_at`, `completed_at`, `error`.

Statuses: `queued`, `running`, `completed`, `failed`, `cancelled`, `dead_letter`. Stop polling when `is_terminal == true`. Call `export_canvas` only when `can_export == true`.

### `list_tasks`
List recent design tasks. Filter by `canvas_id`, `status`, `limit` (max 50). Use this instead of fanning out one `get_task_status` per task when polling >3 tasks at once.

### `cancel_task`
Cancel a running or queued design task. Returns the updated task envelope. No-op on already-terminal tasks. Use when the user changes their mind on an in-flight task or when a bulk batch needs to abort early.

### `remix_design`
Duplicate a canvas; optionally start a design task on the copy. Original is never modified.

| Parameter | Type | Required |
| --- | --- | --- |
| `canvas_id` | string | yes — canvas to duplicate |
| `prompt` | string | no — omit for plain duplicate (synchronous); include to queue a design task |
| `new_name` | string | no — defaults to `"Remix of <original name>"` |
| `brand_kit_id` | string | no — only used when `prompt` is provided |
| `skip_brand_kit` | boolean | default `false`. Pass `true` to apply no brand kit even when the team has a default. |
| `wait` | boolean | default `true` (opposite of `start_design_task`!). Pass `wait=false` for bulk fan-out so calls don't serialize. |

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

`wait` defaults to `true` (block up to ~20s for completion). For large multi-page PDFs or PPTX renders that may exceed the synchronous budget, the call returns `{status: "in_progress", task_id, ...}` instead — poll with `get_export_status` for the final URL.

### `get_export_status`
Poll an async export started by `export_canvas` when it returned `status="in_progress"`. Same shape as `get_task_status`: drive control flow off `is_terminal`. While running, retry after `retry_after_seconds`; on completion, `url` is set; on failure, `error` is set. Export task records are kept for ~1 hour.

| Parameter | Type | Required |
| --- | --- | --- |
| `task_id` | string | yes — the `task_id` from `export_canvas`'s in-progress response |

## Behavioral gotchas

The silent-fail / surprising-behavior set (format defaults, wait asymmetry, concurrency caps, not_ready semantics, brand-kit auto-apply, attachment roles, etc.) is consolidated in [`gotchas.md`](./gotchas.md). Read it before any non-trivial flow.

## Upstream

Canonical catalog with parameter-by-parameter detail and examples: [`docs.moda.app/mcp/tools`](https://docs.moda.app/mcp/tools).
