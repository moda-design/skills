# Bulk variants

**Problem:** The user wants several versions of a design — personalized per persona, per customer, per channel, per brand. Bulk is the workflow that breaks the most "make one design" assumptions in the rest of this skill, so read this in full before fanning out.

There are **three** valid shapes. Pick based on what the user already has and what they want:

| User situation | Pattern |
| --- | --- |
| "Make 10 LinkedIn ads, one per persona" — N independent designs from scratch | **A — fan out `start_design_task`** |
| "Make 10 versions of *this* social post, each tailored differently" — N variants of a source canvas | **B — fan out `remix_design`** (preserves structure) |
| "5-panel IG carousel" — one post with multiple linked panels | **C — single `start_design_task` with `format_category="carousel"`** |

Carousel (Pattern C) is a hard cap of 5 panels — see [`../references/format-category.md`](../references/format-category.md). The rest of this recipe is about A and B.

## The single biggest gotcha — concurrency caps

`start_design_task` and `remix_design` share a **per-team in-flight cap**:

| Plan | Max concurrent tasks |
| --- | --- |
| `free` / `free_beta` | 3 |
| `paid` | 10 |
| `ultra` | 15 |

Fan out N > cap and you'll get an `AgentJobRateLimitError` partway through — surfacing as a tool error from `start_design_task`. The skill's job is to never let the user see that error. Use a **windowed launch**: keep at most `cap` tasks in flight, slot in the next prompt every time one terminates.

If you don't know the user's plan (and you usually won't from the MCP surface alone), default to a window of **3**. Safe everywhere. Bump up only if the first batch shows you have headroom.

## Pattern A — fan out `start_design_task` (N independent designs)

Best when each variant has fundamentally different content: per-persona ad copy, per-customer pitch decks, per-region landing pages. There is no source canvas to preserve structure from.

**User:** "Create 10 LinkedIn ads for our automation tool — each tailored to a different ICP persona: CFOs, CTOs, heads of ops, ..."

**Agent** (after the gate, before fanning out):

> Kicking off 10 LinkedIn ads, one per persona. I'll run them in batches of 3 (concurrency cap) and post each canvas URL as soon as it's ready — you can open them while the others are still rendering.

```python
personas = ["CFOs", "CTOs", "heads of ops", ...]   # the user-provided list
dimensions = dict(format_category="social", format_width=1080, format_height=1080)
window = 3   # safe default; bump up if you know the user has paid/ultra

def build_prompt(persona):
    return f"""
      LinkedIn ad for our automation tool, tailored to {persona}.
      Lead with the single pain point this persona feels most acutely
      and the one metric they measure success on. Bold typography, clean
      layout, one CTA.
    """

in_flight = {}          # persona -> task handle
done = {}               # persona -> terminal status
queue = list(personas)  # to-do

# 1. Seed the window
while len(in_flight) < window and queue:
    p = queue.pop(0)
    in_flight[p] = start_design_task(prompt=build_prompt(p), **dimensions)
    # tell the user immediately — canvas_url is in the queued response
    post(f"Started {p}: {in_flight[p]['canvas_url']}")

# 2. Drain + refill
while in_flight:
    # poll the whole pool in one call — cheaper than N get_task_status calls
    pool = list_tasks(status="running", limit=window * 2)
    pool_ids = {t["task_id"] for t in pool["tasks"]}

    for persona, handle in list(in_flight.items()):
        if handle["task_id"] in pool_ids:
            continue   # still running

        # terminal — fetch full status, file under done, slot in next
        s = get_task_status(task_id=handle["task_id"])
        done[persona] = s
        del in_flight[persona]
        post_done(persona, s)   # deliver this one as it finishes

        if queue:
            p = queue.pop(0)
            in_flight[p] = start_design_task(prompt=build_prompt(p), **dimensions)
            post(f"Started {p}: {in_flight[p]['canvas_url']}")

    sleep(3)   # respect retry_after_seconds from any poll
```

Notes on the loop:

- `list_tasks(status="running", ...)` is one RPC for the whole pool. Beats `get_task_status` × N per tick.
- **Post each canvas URL when the task is queued**, not when it finishes. The user can open it immediately — they'll see the agent's progress in the canvas itself.
- **Deliver each result as it terminates.** Bulk feels much faster when 1/10 done shows up in 90s than when all 10 land together at 8 min.
- `post_done(persona, s)` surfaces `s["error"]` if the task failed. Don't let one bad persona block the rest.

### What goes in the prompt vs the parameters

- **Per-persona detail belongs in the prompt** — rewrite the pain point, metric, and CTA for each. Don't just template `{persona}` into a generic sentence.
- **Dimensions and `format_category` stay constant** across the batch. They're parameters.
- **One brand kit for all** unless the user says otherwise. Omit `brand_kit_id` so each task picks up the team default. Don't fetch the kit per task — fetch once before the loop.

## Pattern B — fan out `remix_design` (N variants of a source canvas)

Best when the user has an existing canvas they're happy with and wants variations *of that design* — same structure, different copy, different brand, different aspect ratio. Remix duplicates the source canvas first, then applies the prompt to the copy. The original is never touched.

**User:** "I love this product flyer — make me 5 versions, one for each of these resellers: [list]. Same layout, swap the logo and the regional pricing."

```python
source_id = "cvs_…"               # the flyer canvas the user pointed at
resellers = [...]                  # 5 items
window = 3

queue = list(resellers)
in_flight = {}

def build_prompt(reseller):
    return f"""
      Customize this flyer for {reseller['name']}:
        - replace the headline price with {reseller['price']}
        - place {reseller['name']}'s logo in the existing logo slot
        - update the contact strip with {reseller['phone']} / {reseller['email']}
      Keep the layout, typography, and brand colors otherwise unchanged.
    """

while len(in_flight) < window and queue:
    r = queue.pop(0)
    in_flight[r["name"]] = remix_design(
      canvas_id=source_id,
      prompt=build_prompt(r),
      new_name=f"Flyer — {r['name']}",
      wait=False,   # ← required; remix_design defaults to wait=True (opposite of start_design_task)
    )
    post(f"Started {r['name']}: {in_flight[r['name']]['canvas_url']}")

# Same drain + refill loop as Pattern A
```

Why remix over `start_design_task(canvas_id=source_id, ...)`:

- **`start_design_task(canvas_id=…)` edits the original.** Five resellers, one canvas — the last one wins. The user loses their template.
- **`remix_design` duplicates first.** Original stays clean; you get N independent copies.
- **Layout / structure / brand kit carry forward automatically.** You only need to specify what changes.

**Gotcha:** `remix_design` defaults to `wait=True` while `start_design_task` defaults to `wait=False`. For bulk fan-out, **always pass `wait=False` explicitly to `remix_design`** — otherwise each call blocks and the windowed launch is serialized.

### Variant: brand-swap across canvases (agency use case)

Pattern B with the same prompt but different `brand_kit_id` per call — "give me this same deck in each of our 5 client brands":

```python
for kit_id in client_kit_ids:
    remix_design(
      canvas_id=source_id,
      brand_kit_id=kit_id,
      new_name=f"Q3 Pitch — {kit_titles[kit_id]}",
      # no prompt — the kit swap alone re-themes the design
    )
```

Without a prompt, `remix_design` is **synchronous** (it's just a copy + brand re-apply), so you can skip the polling loop entirely. With a prompt, it's async like `start_design_task`.

## Recovery: a task in the batch fails

`get_task_status` returns `{status: "failed", error: "…"}` for that task. Common cases:

- **Rate limit** (`AgentJobRateLimitError` text in `error`) — your window is too wide. Drop it by one, retry that persona/reseller.
- **Billing** (out of credits) — stop the whole batch. Tell the user; the remaining queued items would all fail the same way.
- **Validation** — bad prompt or parameters for that one task. Skip it, continue with the rest.
- **Upstream model error** — retry that one task once. If it fails again, skip.

Don't silently retry on `failed` unless you specifically know the error is transient. Surface the persona/reseller that failed so the user can decide.

## Aborting a bulk run mid-flight

If the user changes their mind ("never mind, kill them") or you spot a systemic issue (every task failing the same way), call `cancel_task(task_id)` on each in-flight handle. Already-terminal tasks are no-ops.

## Gotchas

- **Default the window to 3** when you don't know the plan. It's safe on free; it just under-utilizes paid/ultra.
- **Use `list_tasks` to poll the pool, not `get_task_status` × N.** One RPC per tick instead of N.
- **Deliver as each finishes.** Don't sit on results until the whole batch lands.
- **One brand kit for all.** Don't pass `brand_kit_id` per task unless the *intent* is per-task brand swap (Pattern B variant).
- **Per-item prompts need real per-item detail.** Templated `{persona}` in a generic sentence produces 10 generic ads.
- **Don't promise instant delivery.** 10 tasks × 2–10 min each, run in batches of 3, is ~10–30 min wall-clock. Tell the user.
- **Carousel ≠ bulk.** "10 IG carousel panels" violates the 5-panel cap. Push back; offer Pattern A (10 standalone posts) or Pattern C (5 panels in one carousel).

## See also

- [`../references/format-category.md`](../references/format-category.md) — `social` vs `carousel` rules
- [`../references/task-lifecycle.md`](../references/task-lifecycle.md) — poll cadence, terminal states, `list_tasks` semantics
- [`../references/errors-and-retries.md`](../references/errors-and-retries.md) — rate-limit / billing / validation error patterns
- [`pull-existing-canvas.md`](./pull-existing-canvas.md) — single-canvas remix (the non-bulk version of Pattern B)
- [`brief-to-deck.md`](./brief-to-deck.md) — single-task flow for reference
