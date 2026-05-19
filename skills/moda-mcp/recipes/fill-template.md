# Fill a template (content remix, same brand)

**When to use:** The user has a source canvas they like — usually a designed template — and wants a new canvas that **keeps the structure and styling** but swaps in new content. "Make this for our Q3 launch", "fill this template with our customer story". The original canvas is preserved.

## Tool call

```python
start_design_task(
  template_canvas_id="cvs_…",       # the source canvas to copy
  prompt="Fill this template for Acme's Q3 launch. Replace the headline with…",
  # brand_kit_id omitted → the source canvas's brand kit applies on the copy.
  # That's what triggers the "within-team-remix" skill: content swap, not rebrand.
)
```

## What the server does

The server:
1. Copies the source canvas into the caller's team (original untouched).
2. Applies the resolved brand kit to the copy. When it **matches** the source's brand kit (or is omitted with no session preference, so the source's kit is preserved), the agent runs the `within-team-remix` skill — content-only changes.
3. Returns a task handle for the new canvas. Poll `get_task_status` as usual.

## Source canvas access

The source must be readable by the caller's team. `template_canvas_id` accepts **any** canvas the team can read — it doesn't need to be flagged as a template type.

## Mutually exclusive

`template_canvas_id` is mutually exclusive with both `canvas_id` and `conversation_id`. Passing either combination raises a tool error.

## Prompt notes

The agent reads the prompt as a content-edit brief over the existing layout. Be specific about what to replace (headline, body, image, data) and what to keep. If the prompt asks for a rebrand ("change everything to dark mode") you actually want [`rebrand-template.md`](./rebrand-template.md) — pass a different `brand_kit_id`.

## See also

- [`rebrand-template.md`](./rebrand-template.md) — same workflow but pass a different `brand_kit_id` to drive a full rebrand
- [`../recipes/bulk-variants.md`](./bulk-variants.md) — Pattern B uses `template_canvas_id` to fan out N variants
- [`../references/gotchas.md#conversations-vs-canvases-vs-remixes`](../references/gotchas.md#conversations-vs-canvases-vs-remixes) — when to fill a template vs edit in place vs iterate in conversation
