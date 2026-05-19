# Edit an existing canvas

**When to use:** The user wants to modify a canvas they already have, in place. "Add a footer to my deck", "change the headline on slide 2", "fix the date in the resume". The original canvas is mutated.

## Tool call

```python
start_design_task(
  canvas_id="cvs_…",
  prompt="…",
  # format_category, dimensions, brand_kit are inferred from the existing canvas
)
```

## Destructive — call this out to the user

`canvas_id` mutates the source canvas. Five edits → five revisions of the same canvas. If the user wants variations of the canvas while keeping the original clean, use [`fill-template.md`](./fill-template.md) or [`rebrand-template.md`](./rebrand-template.md) instead.

## Mutually exclusive

`canvas_id`, `template_canvas_id`, and `conversation_id` cannot be combined.

- `canvas_id` + `template_canvas_id` → tool error.
- `template_canvas_id` + `conversation_id` → tool error.
- `canvas_id` + `conversation_id` → no error, but `canvas_id` is **silently ignored**. The agent uses the conversation's canvas.

## Iterating in conversation

For follow-up tweaks ("now make the title bigger", "add a third bullet") on the same canvas, pass `conversation_id` from the previous response instead of `canvas_id`. The agent keeps full context of prior turns.

```python
# turn 2: tweak slide 1
start_design_task(
  prompt="Make the title on slide 1 about 30% larger.",
  conversation_id=prior_response["conversation_id"],
)
```

## See also

- [`create-new-design.md`](./create-new-design.md) — start from scratch instead
- [`fill-template.md`](./fill-template.md) — produce a new canvas that mirrors the source structure
- [`../references/gotchas.md#conversations-vs-canvases-vs-remixes`](../references/gotchas.md#conversations-vs-canvases-vs-remixes) — full mutual-exclusion matrix
