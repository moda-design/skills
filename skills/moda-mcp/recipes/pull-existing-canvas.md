# Pull an existing canvas into chat

**Problem:** The user wants to find an existing canvas, pull it into the conversation, and revise it — copy, branding, dimensions, or layout. Example: _"Find my latest social graphic in Moda and pull it in here so we can revise the copy and resize it for LinkedIn."_

## Primitives

- `search_canvases` / `list_my_canvases` — find the canvas
- `get_moda_canvas` — fetch the semantic structure (for the user to review or for the agent to reason about)
- `remix_design` — duplicate + apply edits (original untouched)
- `get_task_status` — poll if the remix has a prompt
- `export_canvas` (optional) — deliver the revised version

## Agent-chat sketch

**User:** "Find my latest social graphic in Moda and pull it in here so we can revise the copy and resize it for LinkedIn."

**Agent** (search first):

```
results = search_canvases(query="social graphic", limit=5)
# pick the most recently updated, or ask the user if ambiguous
```

Agent (to user):

> I found three matches — most recent is "Summer Launch Social" from two days ago. Use that?

**User:** "Yes, and update the copy to emphasize our B2B story, then resize for LinkedIn landscape."

**Agent**:

```
canvas_url = results[0]["url"]          # or [i]["url"] once the user picks
html = get_moda_canvas(url=canvas_url)   # optional — useful if you want to reason about current copy
```

Now remix — duplicate the canvas and kick off a design task on the copy. Original is never modified.

```
task = remix_design(
  canvas_id=results[0]["id"],
  prompt="""
    Rework the copy to emphasize our B2B story — shift from consumer/playful to
    professional/outcome-oriented. Keep the brand colors and general structure
    but resize to LinkedIn landscape (1200×627) and adjust the layout so text
    reads well at that aspect ratio.
  """,
  new_name="Summer Launch Social — LinkedIn",
)
```

Agent (to user):

> Spun up a LinkedIn-landscape remix of "Summer Launch Social." Takes 2–10 min; I'll update you.

**Poll:**

```
# remix_design with a prompt returns a task handle, same as start_design_task
status = get_task_status(task_id=task["task_id"])
while not status["is_terminal"]:
    sleep(status["retry_after_seconds"])
    status = get_task_status(task_id=task["task_id"])
```

**Deliver:**

> Done — here's the LinkedIn version: `<canvas_url>`. Want me to export it as a PNG or JPEG for posting?

## Plain duplicate (no prompt) — synchronous

If the user just wants a copy without edits, `remix_design` without a `prompt` is synchronous:

```
copy = remix_design(canvas_id=results[0]["id"], new_name="Summer Launch Social v2")
# returns immediately — no task_id, no polling
```

## Edit in place vs remix

Pick carefully based on user intent:

| User says | Use |
| --- | --- |
| "edit my deck to add a slide" | `start_design_task(canvas_id=…, prompt="Add a slide about X")` — modifies the existing canvas |
| "make a version of my deck with a new color" | `remix_design(canvas_id=…, prompt="Change colors to …")` — duplicates, edits the copy |
| "duplicate my deck so I can edit it myself" | `remix_design(canvas_id=…)` without a prompt — synchronous plain duplicate |
| "take inspiration from my Q1 deck and make a new one" | `start_design_task(prompt=…, reference_canvas_ids=[q1_id])` — new canvas, original referenced as style |

The default should usually be `remix_design` when the user says "revise," "tweak," or "make a version of." `start_design_task(canvas_id=…)` is destructive — it edits the original.

## Gotchas

- **`search_canvases` returns results ranked by relevance, not recency.** If the user says "latest," you may need to re-sort by `updated_at` — or use `list_my_canvases` (already sorted by most-recent) and filter.
- **Ambiguous matches.** Two similarly-named canvases? Show both, let the user pick.
- **Resizing is a remix, not a copy.** Changing aspect ratio requires the agent to re-lay-out. Use `remix_design` with a prompt that describes the target size.
- **Original is never modified by `remix_design`.** Good for trust; don't tell the user "I updated your social graphic" when you actually remixed it.

## See also

- [`../references/task-lifecycle.md`](../references/task-lifecycle.md) — remix with prompt is async, same poll loop
- [`../SKILL.md`](../SKILL.md) — gate 8 (edit vs new)
- [`iterate-in-conversation.md`](./iterate-in-conversation.md) — refine with `conversation_id` after the remix completes
