---
name: moda-mcp
description: READ THIS FIRST before calling any Moda MCP tool, especially start_design_task. Strongly recommended whenever the Moda MCP server is connected or the user mentions Moda, moda.app, a moda.app/s/ share link, or wants to create, edit, remix, or export a canvas, slide deck, one-pager, ad, social post, Instagram or LinkedIn carousel, PDF report, diagram, UI mockup, or turn a Moda design into code. Covers the 20+ MCP tools, the required prompt-gathering checklist before start_design_task, brand kits, attachments (including the two-step upload for local files), the 2-10 minute async task lifecycle, format_category disambiguation (including carousel), the per-team concurrency cap (3 free / 10 paid / 15 ultra) for bulk fan-out, and the common wrong guesses that break tasks.
---

# moda-mcp

Moda is an AI design agent that creates brand-aligned slides, one-pagers, ads, graphics, and more on a fully editable canvas. The Moda MCP server lets you kick off designs from a conversation — generate from a prompt, spin up variations in bulk, customize a template for a prospect, pull an existing canvas into chat to revise, or turn a Moda canvas into production code.

## When to load this skill

Load this skill whenever **any** of the following is true:

- You are about to call a Moda MCP tool (`set_context`, `get_context`, `list_organizations`, `get_moda_canvas`, `get_moda_canvas_tokens`, `list_moda_canvas_pages`, `list_my_canvases`, `search_canvases`, `list_brand_kits`, `create_brand_kit`, `update_brand_kit`, `set_default_brand_kit`, `delete_brand_kit`, `list_brand_kit_images`, `add_brand_kit_image`, `remove_brand_kit_image`, `upload_file`, `create_upload_url`, `register_uploaded_file`, `start_design_task`, `get_task_status`, `list_tasks`, `cancel_task`, `remix_design`, `export_canvas`, `get_export_status`).
- The user mentions Moda, `moda.app`, or links a `moda.app/s/` share URL.
- The user wants to make a deck, social post, carousel, ad, one-pager, PDF report, diagram, UI mockup, or any other visual asset.
- The user wants to convert an existing Moda canvas to code.

**If you are about to call `start_design_task`, reading this skill — specifically the "Before you call `start_design_task`" section below — is not optional.**

## Prerequisites

- The Moda MCP server is at `https://mcp.moda.app/mcp` (streamable-http transport).
- Authentication is OAuth 2.1 by default (you sign in through the browser on first use). API-key auth with `Authorization: Bearer moda_live_…` is supported for Claude Code, Cursor, VS Code, and HTTP clients — see [`references/authentication.md`](./references/authentication.md).
- In Claude Desktop / claude.ai, the user must enable the **Moda** connector for the current chat (click **+** → **Connectors** → toggle Moda on). If it's off, your tool calls fail before they reach the server.
- Public `moda.app/s/` share links work without authentication. Everything else — listing, searching, creating, editing, exporting — requires auth.

Setup rituals per editor live at [`docs.moda.app/mcp/setup`](https://docs.moda.app/mcp/setup). Don't re-document them in chat; point the user there if the MCP isn't connected.

## Before you call `start_design_task` — HARD GATE

`start_design_task` is the load-bearing tool in this skill. It is easy to misuse. Run through this pre-flight checklist **before every call**, and produce a single consolidated clarifying message when too many gates are unknown.

### Pre-flight checklist

| # | Gate | What to check | If unknown |
| --- | --- | --- | --- |
| 1 | **Format** | What is the user actually making — deck, Instagram post, carousel, LinkedIn post, PDF report, resume, diagram, UI mockup? | Ask. **Do not default to slides silently.** |
| 2 | **Dimensions** | For social / carousel, which platform + orientation? (IG square 1080×1080, IG story 1080×1920, LinkedIn landscape 1080×1350, banner 1200×628) | Ask. Wrong dimensions produce a visually-wrong output. |
| 3 | **Length** | Slide count (state in the prompt — e.g. "10 slides"), or `carousel_page_count` ≤ 5 for carousels | Offer a default ("I'll plan for 10 slides") and move on. |
| 4 | **Audience / tone** | Investors, prospects, internal team, a specific customer? | Ask only if the content doesn't make tone obvious. |
| 5 | **Real content** | Does the user have actual numbers, quotes, customer names, bullet points? Or is the prompt generic? | If generic, **ask**. Never fabricate stats or quotes. |
| 6 | **Brand kit** | Run `list_brand_kits`. Is there a default? | If yes, use it — it applies automatically. If no brand kit exists, offer to create one from their website URL, or confirm `skip_brand_kit=True`. |
| 7 | **References** | Does the user have a deck, screenshot, PDF, or existing Moda canvas to anchor the design? | Use `upload_file` to upload, then pass `{file_id, role}` in `attachments`. For an existing Moda canvas, pass it via `reference_canvas_ids`. |
| 8 | **Edit vs new** | Is the user saying "update the one from March" / "like my Q1 deck" — or is this brand-new? | Search first (`search_canvases`). Then pass `canvas_id` (edit) or `reference_canvas_ids` (inspiration-only; original is not modified). |
| 9 | **Workspace** | Multi-org / multi-team user? | `get_context` at session start. If wrong, `set_context` before creating anything. Context persists 24 hours. |

### Clarifying-question template

When two or more gates are unknown, ask them all in **one** bulleted message with sensible defaults. Don't pepper the user over five turns. Copy this template verbatim and fill in specifics:

```
Before I kick off the design (these usually take 2–10 minutes), a few quick confirmations:

- Format: slide deck (1920×1080) — or did you want a social post, carousel, or PDF?
- Length: I'll plan for 10 slides — let me know if you want more or fewer.
- Brand: I'll use your default brand kit "<kit name>". Say "use <Other> brand" or "no brand" if different.
- Audience: investors? internal team? a specific customer? (affects tone)
- Content: do you have the actual numbers / quotes / bullet points, or should I draft them?
- References: any decks, screenshots, or existing Moda canvases I should mirror? I can upload a file.
```

### Forbidden shortcuts

1. **FORBIDDEN**: calling `start_design_task` without `format_category` when the user asked for anything other than slides. The default layout is slides; a missing category on an Instagram-post request will produce a deck. Always set `format_category` explicitly for non-slide work.
2. **FORBIDDEN**: fabricating content (stats, quotes, customer names, team bios, feature lists) to fill a vague prompt. Ask the user.
3. **FORBIDDEN**: pasting raw URLs into `attachments` when the user has a local file. `upload_file` first, then pass `{file_id, role}`. Role metadata (`source` / `reference` / `asset`) is how the agent decides what to do with each attachment.
4. **FORBIDDEN**: skipping the brand-kit step on a first-run install. If `list_brand_kits` is empty, offer to create one from the user's website URL before running the design task.
5. **FORBIDDEN**: promising sync completion ("give me a second…") on a from-scratch design. Tasks take 2–10 minutes. Tell the user up front.

### When to skip the gate

- **Follow-up iterations via `conversation_id`** — you already have the context from the previous turn. Just pass the prompt.
- **Plain `remix_design` duplicates** without a prompt — synchronous and trivial.
- **`get_moda_canvas` / design-to-code flows** — no design task involved.

## The canonical flow

Every from-scratch design follows this six-step loop:

```
(1) confirm workspace     → get_context / set_context (once per session)
(2) ensure brand kit       → list_brand_kits; create_brand_kit if missing; or skip_brand_kit=True
(3) upload references      → upload_file for any local PDFs / screenshots / images
(4) start the task         → start_design_task with explicit format_category + dimensions (slide count goes in the prompt)
(5) poll until terminal    → get_task_status until can_export == true (or is_terminal with status=failed/cancelled)
(6) deliver                → share canvas_url, offer export_canvas (png / jpeg / pdf / pptx), offer to iterate via conversation_id
```

Minimum viable sketch:

```
context   = get_context()                                            # step 1
kits      = list_brand_kits()                                        # step 2
upload    = upload_file(source_url="https://…/brief.pdf")            # step 3

task = start_design_task(
  prompt="Create a 10-slide pitch deck for FocusTime…",              # slide count goes here
  format_category="slides",
  format_width=1920,
  format_height=1080,
  brand_kit_id=kits["brand_kits"][0]["id"],                          # default kit
  attachments=[{"file_id": upload["id"], "role": "source"}],
)                                                                    # step 4

status = get_task_status(task_id=task["task_id"])                    # step 5
while not status["is_terminal"]:
    wait(status["retry_after_seconds"])                              # ~3s
    status = get_task_status(task_id=task["task_id"])

if status["can_export"]:                                             # step 6
    result = export_canvas(canvas_id=task["canvas_id"], format="pptx")
```

Tell the user at step 4: "This usually takes 2–10 minutes — I'll update you when it finishes." Don't sit silent while polling.

## Core concepts

- **Session context has a 24-hour TTL.** `set_context(org_name=…, team_name=…)` persists across reconnects. All workspace-scoped tools (`list_brand_kits`, `start_design_task`, `remix_design`, `upload_file`) read from it automatically. Pass `org_id` / `team_id` on a single call to override without changing the session default. See [`references/session-context.md`](./references/session-context.md).

- **`start_design_task` is always async.** It returns a task handle immediately; the real work runs 2–10 minutes. Poll `get_task_status(task_id)` at the cadence the server suggests in `retry_after_seconds` (typically ~3s) until `can_export == true` or `is_terminal == true`. Cancellation is supported but rare; failures surface in `status == "failed"` with an `error` message. See [`references/task-lifecycle.md`](./references/task-lifecycle.md).

- **Brand kits auto-apply.** If the team has a default brand kit, every design uses its colors, fonts, logos, and guidelines automatically. Override per-call with `brand_kit_id`, or opt out with `skip_brand_kit=True`. Create one from a website URL (`create_brand_kit(url="https://stripe.com")`) — takes 10–30s. See [`references/brand-kits.md`](./references/brand-kits.md).

- **`format_category` has seven values**, not six: `slides`, `social`, `carousel`, `pdf`, `diagram`, `ui`, `other`. Carousel is a first-class format for Instagram / LinkedIn carousel posts, with its own `carousel_dimensions` (`square` / `linkedin` / `portrait`) and `carousel_page_count` (capped at 5). The default-silent-slides behavior is the single biggest source of wrong outputs. See [`references/format-category.md`](./references/format-category.md).

- **Slide count goes in the prompt, not a parameter.** Say "a 10-slide deck" in the prompt text — the design agent reads it and respects it. There is no dedicated `number_of_slides` MCP parameter. (Carousels are the exception — use `carousel_page_count`, capped at 5.)

- **Attachments have two shapes and three roles.** Prefer the file-id form: `upload_file(source_url=…)` → `{file_id, role: "source" | "reference" | "asset"}`. `source` = extract content from this (a brief PDF). `reference` = emulate this style (a screenshot of a design you like). `asset` = drop this in verbatim (a logo or hero image). The older URL form (`{url, type}`) still works for public hosted URLs but drops role metadata. See [`references/attachments.md`](./references/attachments.md).

- **`export_canvas` returns `not_ready` as a normal state.** When a canvas has an in-flight design task, `export_canvas` returns a structured `{status: "not_ready", reason, retry_after_seconds, task_id}` response — not an error. Wait `retry_after_seconds` and try again. See [`references/errors-and-retries.md`](./references/errors-and-retries.md).

- **Per-team concurrency cap on `start_design_task` + `remix_design`.** `free` / `free_beta` = 3, `paid` = 10, `ultra` = 15. Exceeding the cap surfaces as a tool error on the call that put you over. When fanning out (see [`recipes/bulk-variants.md`](./recipes/bulk-variants.md)), use a **windowed launch** — keep at most `cap` tasks in flight; slot in the next one as each terminates. If you don't know the plan, default the window to 3.

## Common tasks

| User intent | Recipe |
| --- | --- |
| "Create a 10-slide pitch deck for our new AI product…" | [`recipes/brief-to-deck.md`](./recipes/brief-to-deck.md) |
| "Take the attached call notes and create a follow-up deck for this prospect using our sales template." | [`recipes/customize-for-prospect.md`](./recipes/customize-for-prospect.md) |
| "Create 10 versions of this LinkedIn ad, each tailored to a different persona." | [`recipes/bulk-variants.md`](./recipes/bulk-variants.md) |
| "Find my latest social graphic in Moda and pull it in here so we can revise the copy and resize it for LinkedIn." | [`recipes/pull-existing-canvas.md`](./recipes/pull-existing-canvas.md) |
| "Implement the app wireframes from this Moda canvas in React with Tailwind." | [`recipes/design-to-code.md`](./recipes/design-to-code.md) |
| First-run: no brand kit exists yet. | [`recipes/onboard-new-brand.md`](./recipes/onboard-new-brand.md) |
| Iterative refinement ("make the headline bigger / add a testimonial slide"). | [`recipes/iterate-in-conversation.md`](./recipes/iterate-in-conversation.md) |

## Errors & retries

| Condition | What it means | What to do |
| --- | --- | --- |
| `export_canvas` returns `{status: "not_ready", reason: "active_design_job"}` | A design task is still running on this canvas. | Wait `retry_after_seconds` (typically ~3s). Retry `export_canvas`. Not an error. |
| `export_canvas` returns `{status: "not_ready", reason: "task_status_unavailable"}` | Transient; the task-status lookup failed. | Wait `retry_after_seconds`. Retry. |
| `get_task_status` returns `{status: "failed", error: "…"}` | The task failed. Check `error` for the user-visible message. | Surface the error to the user. Don't silently retry — the failure is deterministic. |
| `get_task_status` returns `{status: "cancelled"}` | Someone cancelled the task. | Acknowledge to the user; offer to start fresh. |
| Tool call returns an auth error | OAuth session expired, or API key revoked. | Ask the user to re-authenticate (Claude Desktop: **Settings → Connectors**. Claude Code: `claude /mcp` → re-auth. Cursor: **Settings → MCP**.) |
| `get_moda_canvas` / `list_my_canvases` returns nothing for a moda.app URL | The URL is a private canvas but the user isn't signed in (local stdio server), or the share link was revoked. | Confirm they're on the remote server (`mcp.moda.app`) and authenticated. For share links, ask them to regenerate. |

Full error catalog: [`references/errors-and-retries.md`](./references/errors-and-retries.md).

## Further reading

- [`docs.moda.app/mcp/tools`](https://docs.moda.app/mcp/tools) — canonical tool reference
- [`docs.moda.app/mcp/create-designs`](https://docs.moda.app/mcp/create-designs) — design-creation prompts and patterns
- [`docs.moda.app/mcp/design-to-code`](https://docs.moda.app/mcp/design-to-code) — best practices for turning Moda designs into code
- [`docs.moda.app/mcp/authentication`](https://docs.moda.app/mcp/authentication) — OAuth and API-key auth per client
- [`docs.moda.app/help/ai-agent/prompting`](https://docs.moda.app/help/ai-agent/prompting) — how to write prompts that produce good designs
- [`docs.moda.app/llms.txt`](https://docs.moda.app/llms.txt) / [`docs.moda.app/llms-full.txt`](https://docs.moda.app/llms-full.txt) — plain-text docs for LLMs
