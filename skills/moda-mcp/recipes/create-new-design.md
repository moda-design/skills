# Create a new design

**When to use:** The user wants something built from scratch — no source canvas, no template. "Make me a deck", "create a LinkedIn post", "generate a one-pager".

## Tool call

```python
start_design_task(
  prompt="…",
  format_category="slides",         # required for non-slide intents
  format_width=1920,                # explicit dimensions for predictable output
  format_height=1080,
  # brand_kit_id omitted — session preference (if set) or team default applies
)
```

## Decisions before the call

| Question | How to answer |
| --- | --- |
| What is the user making? | Set `format_category` explicitly: `slides`, `social`, `carousel`, `pdf`, `diagram`, `ui`, `other`. Omitting it defaults to slides. |
| How many slides / panels? | State it in the prompt text ("10-slide deck"). No `number_of_slides` MCP parameter. For carousels use `carousel_page_count` (cap 5). |
| Which brand kit? | If `whoami` showed `brand_kit_count == 1`, just let the default apply. If `> 1` and no session preference is set, ask the user. If they want unbranded, pass `skip_brand_kit=true`. |
| Are there reference materials? | Upload via `upload_file(source_url=…)` and pass `{file_id, role: "source"\|"reference"\|"asset"}` in `attachments`. For existing canvases as inspiration, use `reference_canvas_ids`. |

## Returns

Task handle in milliseconds — `task_id`, `canvas_id`, `canvas_url`, `conversation_id`, `status: "queued"`. Poll `get_task_status(task_id)` at `retry_after_seconds` until `is_terminal == true`.

The succeeded task already carries the finished design **as a rendered file** at `result.export` — `{url, format, status, page_count}`, exported in the canvas's category-default format. Hand that `url` to the user directly. Only call `export_canvas(canvas_id=…, format=…)` when they need a *different* format or a specific page.

## See also

- [`../references/gotchas.md#format-and-dimensions`](../references/gotchas.md#format-and-dimensions) — `format_category` defaults, carousel cap, slide-count placement
- [`edit-existing-canvas.md`](./edit-existing-canvas.md) — when the user has an existing canvas to modify
- [`fill-template.md`](./fill-template.md) — when there's a source canvas to copy + customize
