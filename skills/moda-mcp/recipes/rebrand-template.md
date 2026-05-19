# Rebrand a template (full rebrand on copy)

**When to use:** The user has a source canvas they like and wants a new canvas with a **different brand applied** — different colors, different fonts, different logos. Common for agencies producing the same layout for multiple clients. The original canvas is preserved.

## Tool call

```python
start_design_task(
  template_canvas_id="cvs_…",            # the source design to remix
  brand_kit_id="bk_…",                   # the new brand kit — different from the source's
  prompt="Rebrand this deck for Acme Corp. Apply the new brand kit's colors, fonts, and logos across every slide. Keep the structure.",
)
```

## What the server does

The server:
1. Copies the source canvas into the caller's team (original untouched).
2. Applies the new `brand_kit_id` to the copy.
3. Because the resolved kit **differs from the source's**, the agent runs the `template-remix` skill — full rebrand (palette, typography, hero imagery), not just content swap.
4. Returns a task handle. Poll `get_task_status` as usual.

## Prompt must explicitly ask for a rebrand

The skill needs the prompt to call out that you want colors, fonts, hero imagery, etc. updated to the new brand — otherwise the agent may default to a content-only refresh. Phrases that work: "rebrand for X", "apply the new brand kit across the design", "update colors, fonts, and imagery to the new brand". Per the backend fix in PR #5652, this is a deliberate signal to the agent.

## Picking the new `brand_kit_id`

- If `whoami` returned `brand_kit_count > 1`, you may already have the right id in hand from a recent `find_brand_kits` call or session preference. Use it.
- If unsure, call `find_brand_kits` (JSON-only) and pick by name. Don't call `list_brand_kits` autonomously — it renders the visual showcase the user didn't ask for.

## Mutually exclusive

`template_canvas_id` is mutually exclusive with both `canvas_id` and `conversation_id`.

## Bulk variant — different brand per output

For "produce N rebranded variants, one per client", iterate `start_design_task` calls with the same `template_canvas_id` and a different `brand_kit_id` each call. Pattern B of [`bulk-variants.md`](./bulk-variants.md) covers the windowed-launch shape.

## See also

- [`fill-template.md`](./fill-template.md) — same workflow but keep the source's brand (content-only remix)
- [`bulk-variants.md`](./bulk-variants.md) — fan out rebrands across multiple brand kits
- [`../references/gotchas.md#brand-kits`](../references/gotchas.md#brand-kits) — brand-kit resolution order, `find_` vs `list_` distinction
