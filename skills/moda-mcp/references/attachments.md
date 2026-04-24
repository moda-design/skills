# Attachments

Attachments are how you give Moda's design agent source material, style references, or assets to drop in. They attach to `start_design_task` (and `remix_design` by way of the underlying task) via the `attachments` parameter.

## Two shapes

### File-id form (preferred)

```
upload = upload_file(source_url="https://example.com/brief.pdf")
# → { id: "file_01HT9…", url: "…", filename: "brief.pdf", mime_type: "application/pdf", ... }

start_design_task(
  prompt="Build a pitch deck from this brief",
  attachments=[
    { "file_id": upload["id"], "role": "source", "label": "Q2 strategy brief" },
  ],
)
```

Use this form for anything the user has locally (a PDF, a screenshot, a reference image). It carries **role metadata** — the agent knows what to do with each attachment.

### URL form (legacy, public hosted URLs only)

```
start_design_task(
  prompt="Match this landing page's style",
  attachments=[
    { "url": "https://example.com/reference.png", "type": "image" },
  ],
)
```

Role metadata is dropped — the agent infers use. Use only when the asset is already hosted publicly and you don't want the extra `upload_file` roundtrip.

You can **mix shapes** in one `attachments` list.

## Roles

| Role | Meaning | Example |
| --- | --- | --- |
| `source` | Extract content from this file. Use its text, data, or structure as the deck's source of truth. | Brief PDF, meeting notes DOCX, call transcript |
| `reference` | Emulate this file's style. Don't copy its content — match its look, layout, feel. | Screenshot of a design you like, mood board image |
| `asset` | Use this file directly in the output. Drop it in verbatim. | Logo, hero image, customer photo |

Picking the right role matters. Passing a brief PDF as `reference` means the agent mimics the PDF's formatting; passing it as `source` means it uses the PDF's text. Passing a logo as `reference` means the agent tries to emulate the logo's style; as `asset`, it places the actual logo in the design.

## Supported file types

- Images: PNG, JPEG, WebP
- Documents: PDF, PPTX
- (URL form also supports `url` as a type, meaning the agent will fetch the web page)

## Deduplication

`upload_file` hashes content. Uploading the same file twice returns `{ was_duplicate: true, id, url, ... }` with the existing record. Safe to call repeatedly on the same URL — Moda won't store duplicates.

## `reference_canvas_ids` — an alternative to attachments

For existing Moda canvases as inspiration, don't upload a screenshot — pass the canvas ID in `reference_canvas_ids` directly:

```
start_design_task(
  prompt="Create a similar landing page in our new brand",
  reference_canvas_ids=["cvs_01HT9…", "cvs_01HT9…"],
)
```

The agent can see the referenced designs' structure and style natively. Original canvases are never modified.

## When to use which

| User situation | Use |
| --- | --- |
| "Here's our call notes — build a follow-up deck" (PDF or DOCX) | `upload_file` + `{file_id, role: "source"}` |
| "Match the style of this screenshot" (image file on disk) | `upload_file` + `{file_id, role: "reference"}` |
| "Use our logo" (image file on disk) | `upload_file` + `{file_id, role: "asset"}` |
| "Here's a landing page I like" (URL to a web page) | `{url: "…", type: "url"}` — agent scrapes the page |
| "Make a variant of my Q1 deck" (existing Moda canvas) | `reference_canvas_ids=["cvs_…"]` |

## Worked example

User: "Take the attached Q2 strategy PDF and build a pitch deck in the style of the Stripe homepage screenshot. Use our logo on the title slide."

```
brief = upload_file(source_url="https://…/q2-strategy.pdf")
style = upload_file(source_url="https://…/stripe-homepage.png")
logo  = upload_file(source_url="https://…/acme-logo.svg")

start_design_task(
  prompt="Build a 12-slide pitch deck from the attached Q2 strategy. "
         "Match the Stripe-homepage visual style. Place the Acme logo on the title slide.",
  format_category="slides",
  format_width=1920,
  format_height=1080,
  number_of_slides=12,
  attachments=[
    { "file_id": brief["id"], "role": "source", "label": "Q2 strategy brief" },
    { "file_id": style["id"], "role": "reference", "label": "Stripe homepage" },
    { "file_id": logo["id"],  "role": "asset",     "label": "Acme logo" },
  ],
)
```

## Common wrong guesses

- **Using the URL form when the user has a local file.** The role metadata from file-id form materially improves output. `upload_file` first.
- **Passing a logo as `reference`.** The agent emulates its style rather than placing it. Use `asset` when you want the actual file in the design.
- **Passing a brief as `reference`.** The agent mimics the brief's formatting rather than using its content. Use `source`.
- **Re-uploading the same file in every turn.** Moda deduplicates, but you still pay a roundtrip. Cache the `file_id` in your own memory for the session.
- **Forgetting `reference_canvas_ids` exists.** If the user points at a Moda canvas as inspiration, use the canvas ID directly — don't export to PNG and re-upload.

## Upstream

- [`docs.moda.app/mcp/tools#upload_file`](https://docs.moda.app/mcp/tools#upload_file)
- [`docs.moda.app/mcp/tools#start_design_task`](https://docs.moda.app/mcp/tools#start_design_task) — attachments parameter
