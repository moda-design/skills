# Bulk variants

**Problem:** The user wants several versions of a design — personalized per persona, per customer, per channel, per brand. Bulk is the workflow that breaks the most "make one design" assumptions in the rest of this skill, so read this in full before fanning out.

There are **three** valid shapes. Pick based on what the user already has and what they want:

| User situation | Pattern |
| --- | --- |
| "Make 10 LinkedIn ads, one per persona" — N independent designs from scratch | **A — fan out `start_design_task`** |
| "Make 10 versions of *this* canvas" / "rebrand this template for each of our 5 clients" — N variants of a source canvas, with or without per-variant brand swap | **B — fan out `start_design_task` with `template_canvas_id`** (preserves structure; server auto-picks content-only remix vs full rebrand) |
| "5-panel IG carousel" — one post with multiple linked panels | **C — single `start_design_task` with `format_category="carousel"`** |

Carousel (Pattern C) is a hard cap of 5 panels — see [`../references/gotchas.md#format-and-dimensions`](../references/gotchas.md#format-and-dimensions). The rest of this recipe is about A and B.

## The single biggest gotcha — concurrency caps

`start_design_task` and `remix_design` share a **per-team in-flight cap**:

| Plan | Max concurrent tasks |
| --- | --- |
| `free` / `free_beta` | 3 |
| `paid` | 10 |
| `ultra` / `enterprise` | 15 |

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

## Pattern B — fan out `start_design_task` with `template_canvas_id` (N variants of a source canvas)

Best when the user has an existing canvas they're happy with and wants variations *of that design* — same structure, different copy, different brand. The server copies the source, applies the resolved brand kit on the copy, then runs the agent against the copy. The original is never touched.

Skill selection is automatic from brand-kit comparison:
- Same brand kit as the source → content-only remix (preserve design, swap content)
- Different `brand_kit_id` → full rebrand (rework colors, fonts, copy, imagery)
- `skip_brand_kit=True` → no forced skill; the curator decides

**User:** "I love this product flyer — make me 5 versions, one for each of these resellers: [list]. Same layout, swap the logo and the regional pricing."

```python
source_id = "cvs_…"               # the flyer canvas the user pointed at
resellers = [...]                  # 5 items, each with optional brand_kit_id for per-client rebrand
window = 3

queue = list(resellers)
in_flight = {}

def build_prompt(reseller):
    return f"""
      Customize this flyer for {reseller['name']}:
        - replace the headline price with {reseller['price']}
        - update the contact strip with {reseller['phone']} / {reseller['email']}
    """

while len(in_flight) < window and queue:
    r = queue.pop(0)
    in_flight[r["name"]] = start_design_task(
      template_canvas_id=source_id,
      prompt=build_prompt(r),
      brand_kit_id=r.get("brand_kit_id"),   # per-client brand if rebranding; omit for same-brand fill
      canvas_name=f"Flyer — {r['name']}",
      # wait defaults to False on start_design_task — handle returned immediately
    )
    post(f"Started {r['name']}: {in_flight[r['name']]['canvas_url']}")

# Same drain + refill loop as Pattern A
```

Why `template_canvas_id` over `start_design_task(canvas_id=source_id, ...)`:

- **`canvas_id` edits the original.** Five resellers, one canvas — the last one wins. The user loses their template.
- **`template_canvas_id` duplicates first.** Original stays clean; you get N independent copies.
- **Layout / structure carry forward automatically.** You only specify what changes in the prompt.
- **Per-variant brand swap is first-class.** Pass a different `brand_kit_id` per call to produce the same design rebranded for each client.

**Note:** `template_canvas_id` is mutually exclusive with both `canvas_id` and `conversation_id` — passing either combination raises a tool error. See [`../references/gotchas.md#conversations-vs-canvases-vs-remixes`](../references/gotchas.md#conversations-vs-canvases-vs-remixes) for the full matrix.

### When to use `remix_design` instead

`remix_design(canvas_id=…)` without a prompt is a **synchronous plain duplicate** — useful when the user just wants a copy they'll edit themselves. With a prompt, it's an older async path that pre-dates `template_canvas_id`; prefer `template_canvas_id` for new bulk flows (cleaner brand-kit handling, automatic skill selection, no `wait` default asymmetry).

## Recovery: a task in the batch fails

`get_task_status` returns `{status: "failed", error: "…"}` for that task. Common cases:

- **Rate limit** (`AgentJobRateLimitError` text in `error`) — your window is too wide. Drop it by one, retry that persona/reseller.
- **Billing** (out of credits) — stop the whole batch. Tell the user; the remaining queued items would all fail the same way.
- **Validation** — bad prompt or parameters for that one task. Skip it, continue with the rest.
- **Upstream model error** — retry that one task once. If it fails again, skip.

Don't silently retry on `failed` unless you specifically know the error is transient. Surface the persona/reseller that failed so the user can decide.

## Aborting a bulk run mid-flight

If the user changes their mind ("never mind, kill them") or you spot a systemic issue (every task failing the same way), call `cancel_task(task_id)` on each in-flight handle. Already-terminal tasks are no-ops.

## See also

- [`../references/gotchas.md`](../references/gotchas.md) — `wait` asymmetry, concurrency caps, format defaults, carousel cap, `not_ready` retry, and the rest of the silent-fail set
- [`../references/tools.md`](../references/tools.md) — full signatures for `start_design_task`, `remix_design`, `list_tasks`, `cancel_task`
