# Iterate in conversation

**Problem:** A design is done. The user wants small changes — different headline, added slide, dark mode, resize. Don't start fresh; continue the conversation using `conversation_id` so the agent keeps full context of the design and prior turns.

## Primitives

- `start_design_task` with `conversation_id` — resume the prior conversation
- `get_task_status` — poll (same as the first turn)

## Agent-chat sketch

**Turn 1** — initial design (already done in a previous message):

```
task1 = start_design_task(
  prompt="Create a 10-slide pitch deck for FocusTime...",
  format_category="slides",
)
# → { task_id, canvas_id, canvas_url, conversation_id: "conv_01HT9…", ... }

status = get_task_status(task_id=task1["task_id"])
# (poll until done; share canvas_url with user)
```

**Turn 2** — user: "Make the headline on slide 1 bigger and switch to a dark background."

**Agent** — skip the prompt-gathering gate (the agent already has full context from the prior turn). Just pass the change with the conversation_id:

```
task2 = start_design_task(
  prompt="On slide 1, make the headline 1.5x bigger. Switch the whole deck to a dark background with light text.",
  conversation_id=task1["conversation_id"],
)
# canvas_id is automatically the conversation's canvas — even if you passed it, it's ignored
```

**Poll + deliver** as before. The canvas URL stays the same (same canvas, updated in place).

## What resumes

When you pass `conversation_id`, the agent has access to:

- The full prior prompt.
- The prior design decisions (what went on each slide, which brand kit applied, the format category).
- Attachments and references from prior turns.

You do **not** need to re-state the format, brand, or structural context. Just the change.

## What does not resume

- **`canvas_id` is ignored when resuming.** The agent uses the conversation's canvas automatically.
- **New attachments are additive within the conversation**, but if the user wants to replace an old reference, say so in the prompt.

## Follow-up examples

| User says | Agent prompt |
| --- | --- |
| "Make the headline bigger" | `"Make the main headline on slide 1 roughly 1.5x larger."` |
| "Add a testimonial slide after slide 3" | `"Insert a new slide between slide 3 and slide 4 — customer testimonial layout. Use a short quote + attribution placeholder."` |
| "Switch to dark mode" | `"Switch the whole deck to a dark background with light text. Keep brand colors for accents."` |
| "Replace the stock image on slide 2" | `"Replace the image on slide 2 with something more product-focused — keep the composition similar."` |
| "Make it less corporate" | `"Make the overall feel less formal — friendlier typography, warmer color accents, more whitespace."` |

## When to break out of the conversation

Start a fresh task (no `conversation_id`) when:

- The user wants a **brand-new canvas** (different topic, different format, different brand).
- The user wants to **fork** — "I like this deck, but let me see a completely different version." Use `remix_design` instead; it duplicates the canvas so the original is preserved.
- The conversation is old (> 24 hours). Still works, but context may be stale — consider starting fresh.

## Gotchas

- **Don't run the prompt-gathering gate on follow-ups.** You already have context. Re-asking "what format? what length? what brand?" is annoying.
- **Don't pass `canvas_id` when resuming.** It's silently ignored, so harmless — but makes the intent unclear in logs.
- **Every turn is still 2–10 minutes.** Iteration isn't synchronous. Tell the user: "Applying those changes — back in a few minutes."
- **Conversation ID comes in every response**, both `start_design_task` and `get_task_status`. Use whichever is freshest.
- **Large structural changes should be a remix.** "Turn this deck into a completely different presentation about X" — use `remix_design`, not a conversation follow-up.

## See also

- [`../references/task-lifecycle.md`](../references/task-lifecycle.md) — conversation_id semantics
- [`brief-to-deck.md`](./brief-to-deck.md) — turn 1 of this pattern
- [`pull-existing-canvas.md`](./pull-existing-canvas.md) — `remix_design` when you want a fork instead of an edit
