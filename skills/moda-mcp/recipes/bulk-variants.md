# Bulk variants

**Problem:** The user wants several versions of the same design, each tailored differently. Example: _"Create 10 versions of this LinkedIn ad, each tailored to a different persona in our ICP."_

There are two valid shapes. Pick based on user intent.

## Primitives

- `start_design_task` — fan out in parallel (for N separate canvases)
- `get_task_status` — poll each
- `remix_design` (optional) — if there's an existing canvas to start from
- For carousel (single post, multiple panels): one `start_design_task` with `format_category="carousel"` + `carousel_page_count`

## Pattern A — N separate canvases (ten ads = ten canvases)

This is the common interpretation of "10 versions of this ad." Each variant is its own standalone canvas.

**Agent-chat sketch:**

User: "Create 10 versions of this LinkedIn ad for our automation tool — each tailored to a different ICP persona. Personas: CFOs, CTOs, heads of ops, ..."

Agent (gate, then):

> Kicking off 10 LinkedIn ads, one per persona. Each takes 2–10 minutes; I'll run them in parallel and update you as they finish.

```
personas = ["CFOs", "CTOs", "heads of ops", ...]           # user-provided list of 10
dimensions = { "format_category": "social",
               "format_width": 1080, "format_height": 1080 }  # LinkedIn square

tasks = []
for persona in personas:
    t = start_design_task(
      prompt=f"""
        Create a LinkedIn ad for our automation tool tailored to {persona}.
        Emphasize the pain point they feel most acutely and the single metric
        they care about. Bold typography, clean layout, one CTA.
      """,
      **dimensions,
    )
    tasks.append((persona, t))
```

**Poll all of them** (sequential polling or a concurrency-capped pool — don't hammer):

```
done = {}
while len(done) < len(tasks):
    for persona, t in tasks:
        if persona in done:
            continue
        status = get_task_status(task_id=t["task_id"])
        if status["is_terminal"]:
            done[persona] = status
    sleep(3)                                              # server's hint
```

**Deliver:** list the canvas URLs grouped by persona. If any failed, surface the error for that one only and offer to retry.

## Pattern B — one carousel (single post, up to 5 panels)

Only when the user actually wants an Instagram or LinkedIn **carousel post** — one post, multiple linked panels. Hard cap: 5 panels.

If the user says "5-panel Instagram carousel" / "LinkedIn carousel," this is the pattern:

```
task = start_design_task(
  prompt="""
    5-panel Instagram carousel for our summer sale (20% off everything).
    Panel 1: hook / product photo. Panels 2–4: three reasons to buy.
    Panel 5: clear CTA with promo code.
  """,
  format_category="carousel",
  carousel_dimensions="square",     # or "linkedin" / "portrait"
  carousel_page_count=5,
)
```

Treated as a single task; single `get_task_status` poll; single canvas URL.

## Which pattern did the user mean?

| User phrasing | Pattern |
| --- | --- |
| "10 versions of an ad, one per persona" | A (10 separate canvases) |
| "10 LinkedIn carousel panels" | A — but push back: carousels cap at 5, so either reduce to 5 panels (Pattern B) or produce 10 standalone social posts (Pattern A) |
| "5-panel IG carousel" | B |
| "carousel with 3 slides" | B, `carousel_page_count=3` |
| "a few variants to A/B test" | A — two or three standalone posts |

If the phrasing is ambiguous (e.g. "10 Instagram posts"), ask once: "Do you want 10 separate Instagram posts, or one IG carousel with several panels?"

## Gotchas

- **Respect `retry_after_seconds` across the whole pool.** Don't poll every task every second. Round-robin through the pool at the server's cadence.
- **Cap parallelism.** 10 tasks in flight is fine; 100 might trigger the team's concurrency limit. If you see rate-limit errors in task status, serialize.
- **Per-persona prompts need real persona detail.** Don't just insert `{persona}` — rewrite the pain point, metric, and CTA for each.
- **One brand kit for all.** All 10 variants use the team default (unless the user says otherwise). Don't pass `brand_kit_id` per task.
- **Don't promise instant delivery.** 10 tasks × 2–10 min each = all 10 done in roughly 2–10 min (parallel). Tell the user.

## See also

- [`../references/format-category.md`](../references/format-category.md) — social vs carousel rules
- [`../references/task-lifecycle.md`](../references/task-lifecycle.md) — polling cadence, terminal states
- [`brief-to-deck.md`](./brief-to-deck.md) — single-task flow for reference
