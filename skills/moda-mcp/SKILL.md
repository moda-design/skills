---
name: moda-mcp
description: READ THIS BEFORE calling any Moda MCP tool. Recommended whenever the Moda MCP server is connected or the user mentions Moda, moda.app, a moda.app/s/ share link, or wants to create, edit, remix, or export a canvas (slide deck, social post, Instagram or LinkedIn carousel, PDF report, diagram, UI mockup), or turn a Moda canvas into code. Always call ``whoami`` first to learn the active workspace, brand-kit count, plan tier, and concurrency cap, then open the matching design-task recipe (create-new-design, edit-existing-canvas, fill-template, rebrand-template, or bulk-variants) before calling ``start_design_task``. Also covers the gotchas that silently go wrong — format_category default, the wait-default asymmetry between start_design_task and remix_design, the per-team concurrency cap, the carousel 5-panel cap, the not_ready export retry state, conversation_id semantics, attachment shapes, and the ``find_brand_kits`` vs ``list_brand_kits`` split.
---

# moda-mcp

Moda is an AI design agent. The MCP server at `https://mcp.moda.app/mcp` lets you create designs from a prompt, remix existing canvases, and export to PNG / JPEG / PDF / PPTX. Public share links (`moda.app/s/…`) work unauthenticated; everything else requires OAuth (default in Claude / Cursor / VS Code / Gemini CLI) or an API key (`moda_live_…` for scripts, CI, scheduled jobs).

## Call `whoami` first

On any new conversation, call `whoami` before doing anything else. It returns identity + active workspace + entitlements in one payload (~no UI, no side effects) and lets you skip a lot of downstream tool calls:

- `org_count == 1` → the user has one organization; no need to call `list_organizations` or ask which workspace to use.
- `brand_kit_count == 1` → use `team_default_brand_kit.id` directly; don't call `find_brand_kits`.
- `brand_kit_count == 0` → no kit exists; offer `create_brand_kit(url=…)` or proceed with `skip_brand_kit=true`.
- `concurrency_cap` → the bulk fan-out window for this plan (3 free / 10 paid / 15 ultra/enterprise). Use it instead of defaulting to 3.
- `session.brand_kit_id` → if non-null, the user has pinned a kit for this session; honor it.

If `whoami` shows `org_count > 1` and the active session isn't set, call `set_context(org_name=…)` (or ask the user) before any workspace-scoped tool.

## Pick a design-task recipe

After `whoami`, the next thing to do is match the user's intent to one of five canonical workflows. **Open the matching recipe before calling `start_design_task`** — each one covers the right parameters, what's preserved vs mutated, and what to surface back to the user.

| User intent | Recipe |
| --- | --- |
| Build something from scratch ("make me a deck", "create a LinkedIn post") | [`recipes/create-new-design.md`](./recipes/create-new-design.md) |
| Modify a canvas in place ("add a footer to my deck") — **destructive** | [`recipes/edit-existing-canvas.md`](./recipes/edit-existing-canvas.md) |
| Fill a template with new content, same brand | [`recipes/fill-template.md`](./recipes/fill-template.md) |
| Rebrand a template for a different brand kit | [`recipes/rebrand-template.md`](./recipes/rebrand-template.md) |
| Fan out N variants in parallel (windowed launch, concurrency cap) | [`recipes/bulk-variants.md`](./recipes/bulk-variants.md) |

Most "design something" requests fit one of these. Picking the right one up front avoids the most common failure modes.

## Tool catalog

25+ tools across session context, canvas read, design-to-code, brand kits, uploads, design tasks, and export. Full signatures with defaults: [`references/tools.md`](./references/tools.md).

## Gotchas — what silently goes wrong

The recipes above are the happy paths. This list is the corrections / corner cases — consult [`references/gotchas.md`](./references/gotchas.md) when something surprises you, when you're about to do something the recipes don't cover, or before any non-trivial flow.

1. **`format_category` silently defaults to slides** on `start_design_task`. Always pass it explicitly for social, carousel, pdf, diagram, ui, or other.
2. **Slide count goes in the prompt text**, not a parameter. The REST API exposes `number_of_slides`; the MCP server does not.
3. **`remix_design` defaults to `wait=True`** — opposite of `start_design_task`'s `wait=False`. For bulk fan-out, pass `wait=False` explicitly or each call blocks in series.
4. **Per-team concurrency cap on design tasks**: `free` / `free_beta` = 3, `paid` = 10, `ultra` / `enterprise` = 15. Exceeding it errors out the call. Use a windowed launch for bulk; default the window to 3 when the plan is unknown.
5. **Carousel cap = 5 panels** (`carousel_page_count`). "10 IG carousel slides" violates the cap — offer 5 panels or 10 standalone social posts.
6. **Canvas-target parameters on `start_design_task` interact carefully.** `template_canvas_id` (fork a source into a new canvas, with optional brand swap) is mutually exclusive with both `canvas_id` (edit existing in place) and `conversation_id` (keep iterating) — passing either pair raises a tool error. `canvas_id` + `conversation_id` together does NOT error: `canvas_id` is silently ignored and the agent uses the conversation's canvas.
7. **`export_canvas` `{status: "not_ready"}` is a retry state, not an error** — returned while a design task is still running on the canvas. Retry after `retry_after_seconds`.
8. **Large exports return `{status: "in_progress", task_id}`** when they exceed the sync budget. Poll `get_export_status` for the URL.
9. **Brand-kit resolution order** on `start_design_task` / `remix_design`: explicit `brand_kit_id` → session preference (from `set_session_brand_kit` or the showcase iframe's "Use for this session" button) → team default → none (only if `skip_brand_kit=true`). Don't restate colors / fonts / logos in the prompt — the resolved kit owns them.
10. **`find_brand_kits` for lookups; `list_brand_kits` only when the user asks to see them.** Both return the same data, but `list_brand_kits` renders a visual showcase iframe on **every** call (per the MCP Apps spec, can't be suppressed per-call). Use `find_brand_kits` when picking a `brand_kit_id` for another tool.
11. **Attachments have two shapes**: `{file_id, role}` (preferred — carries `role` ∈ `source` / `reference` / `asset` that changes agent behavior) and `{url, type}` (legacy, drops role metadata).

## Setup & auth

Per-editor install: [`docs.moda.app/mcp/setup`](https://docs.moda.app/mcp/setup). OAuth vs API-key tradeoffs: [`docs.moda.app/mcp/authentication`](https://docs.moda.app/mcp/authentication). In Claude Desktop / claude.ai, the user must enable the **Moda** connector for the current chat (click **+** → **Connectors**) before any tool call works.
