---
name: moda-mcp
description: READ THIS BEFORE calling any Moda MCP tool. Recommended whenever the Moda MCP server is connected or the user mentions Moda, moda.app, a moda.app/s/ share link, or wants to create, edit, remix, or export a canvas (slide deck, social post, Instagram or LinkedIn carousel, PDF report, diagram, UI mockup), or turn a Moda canvas into code. Covers the things that silently go wrong — format_category default, the wait-default asymmetry between start_design_task and remix_design, the per-team concurrency cap for bulk fan-out, the carousel 5-panel cap, the not_ready export retry state, conversation_id semantics, and the two attachment shapes — plus pointers to the tool catalog, gotchas reference, and bulk-variants recipe.
---

# moda-mcp

Moda is an AI design agent. The MCP server at `https://mcp.moda.app/mcp` lets you create designs from a prompt, remix existing canvases, and export to PNG / JPEG / PDF / PPTX. Public share links (`moda.app/s/…`) work unauthenticated; everything else requires OAuth (default in Claude / Cursor / VS Code / Gemini CLI) or an API key (`moda_live_…` for scripts, CI, scheduled jobs).

## What goes silently wrong

These are the failure modes you can't see from tool signatures alone. Read [`references/gotchas.md`](./references/gotchas.md) before any non-trivial flow.

1. **`format_category` silently defaults to slides** on `start_design_task`. Always pass it explicitly for social, carousel, pdf, diagram, ui, or other.
2. **Slide count goes in the prompt text**, not a parameter. The REST API exposes `number_of_slides`; the MCP server does not.
3. **`remix_design` defaults to `wait=True`** — opposite of `start_design_task`'s `wait=False`. For bulk fan-out, pass `wait=False` explicitly or each call blocks in series.
4. **Per-team concurrency cap on design tasks**: `free` / `free_beta` = 3, `paid` = 10, `ultra` / `enterprise` = 15. Exceeding it errors out the call. Use a windowed launch for bulk; default the window to 3 when the plan is unknown.
5. **Carousel cap = 5 panels** (`carousel_page_count`). "10 IG carousel slides" violates the cap — offer 5 panels or 10 standalone social posts.
6. **Canvas-target parameters on `start_design_task` interact carefully.** `template_canvas_id` (fork a source into a new canvas, with optional brand swap) is mutually exclusive with both `canvas_id` (edit existing in place) and `conversation_id` (keep iterating) — passing either pair raises a tool error. `canvas_id` + `conversation_id` together does NOT error: `canvas_id` is silently ignored and the agent uses the conversation's canvas.
7. **`export_canvas` `{status: "not_ready"}` is a retry state, not an error** — returned while a design task is still running on the canvas. Retry after `retry_after_seconds`.
8. **Large exports return `{status: "in_progress", task_id}`** when they exceed the sync budget. Poll `get_export_status` for the URL.
9. **Brand kits auto-apply** — the team default styles every design unless you pass `skip_brand_kit=True`. Don't restate colors / fonts / logos in the prompt; that fights the kit.
10. **Attachments have two shapes**: `{file_id, role}` (preferred — carries `role` ∈ `source` / `reference` / `asset` that changes agent behavior) and `{url, type}` (legacy, drops role metadata).

## Tool catalog

25+ tools across session context, canvas read, design-to-code, brand kits, uploads, design tasks, and export. Full signatures with defaults: [`references/tools.md`](./references/tools.md).

## Bulk fan-out

The most-asked workflow ("make 10 variations of this") has non-obvious patterns: which tool to use, how to respect the concurrency cap, how to poll efficiently. See [`recipes/bulk-variants.md`](./recipes/bulk-variants.md).

## Setup & auth

Per-editor install: [`docs.moda.app/mcp/setup`](https://docs.moda.app/mcp/setup). OAuth vs API-key tradeoffs: [`docs.moda.app/mcp/authentication`](https://docs.moda.app/mcp/authentication). In Claude Desktop / claude.ai, the user must enable the **Moda** connector for the current chat (click **+** → **Connectors**) before any tool call works.
