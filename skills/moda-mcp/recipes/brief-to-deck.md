# Brief to deck

**Problem:** The user wants a pitch deck from a prompt. Example: _"Create a 10-slide pitch deck for our new AI product. Cover problem, solution, product, market, traction, team, and ask. Keep it clean, modern, and on-brand."_

## Primitives

- `get_context` — confirm workspace
- `list_brand_kits` — find the default kit
- `start_design_task` — kick off the design
- `get_task_status` — poll to completion
- `export_canvas` (optional) — deliver as PPTX or PDF

## Agent-chat sketch

**User:** "Create a 10-slide pitch deck for our new AI product. Cover problem, solution, product, market, traction, team, and ask. Keep it clean, modern, and on-brand."

**Agent** (runs the prompt-gathering gate internally):

```
get_context()                           # already set; Acme Corp / Design Team
list_brand_kits()                       # → "Acme Corp" kit, is_default: true
```

Most gates are covered by the prompt: format is slides, length is 10, content is listed, brand is default, no references mentioned, new canvas. Audience is implied (investors). No clarification needed; proceed.

**Agent** (to user, before calling the tool):

> Kicking off a 10-slide pitch deck with your default "Acme Corp" brand kit. This usually takes 2–10 minutes — I'll update you when it's ready.

**Agent** (tool call):

```
task = start_design_task(
  prompt="""
    Create a 10-slide pitch deck for our new AI product. Structure:
      1. Title
      2. Problem
      3. Solution
      4. Product overview
      5. Market opportunity
      6. Traction
      7. Team
      8. Ask
      9. Closing / contact
      (1 buffer slide for customization)
    Tone: clean, modern, investor-appropriate. Use real headers and concise body copy.
  """,
  format_category="slides",
  format_width=1920,
  format_height=1080,
)
# Slide count ("10-slide") comes from the prompt — there's no dedicated MCP parameter.
# → task_id, canvas_id, canvas_url, conversation_id, status: "queued", retry_after_seconds: 3
```

**Agent** (poll):

```
while not status["is_terminal"]:
    sleep(status["retry_after_seconds"])
    status = get_task_status(task_id=task["task_id"])
    # every ~30s, post a short progress message if current_step has changed
```

**Agent** (on completion):

> Done — here's your deck: `<canvas_url>`. Want me to export it as a PPTX, or iterate on specific slides? (I'll keep the conversation context so you can say things like "make the headline bigger" or "swap slide 4 for a product demo.")

If the user asks to export:

```
export_canvas(canvas_id=task["canvas_id"], format="pptx")
# → { status: "completed", url: "https://storage.googleapis.com/.../deck.pptx", format: "pptx" }
```

## Gotchas

- **If `list_brand_kits` is empty** on a first-run team, stop and offer to create one from the user's website URL before calling `start_design_task`. See [`onboard-new-brand.md`](./onboard-new-brand.md).
- **Don't fabricate content.** If the user's prompt is generic ("a pitch deck for our startup"), ask for the actual story, metrics, and team bios. Never invent stats.
- **State the slide count in the prompt.** "10-slide deck" in the prompt text is how the agent picks length — there's no dedicated `number_of_slides` MCP parameter (the REST API has one, but the MCP server doesn't expose it).
- **The conversation stays alive** via `task["conversation_id"]`. Iterations ("make the headline bigger") should pass it back, not start fresh.

## See also

- [`../SKILL.md`](../SKILL.md) — the prompt-gathering gate
- [`../references/task-lifecycle.md`](../references/task-lifecycle.md) — poll cadence, terminal states
- [`../references/format-category.md`](../references/format-category.md) — the seven format values
- [`iterate-in-conversation.md`](./iterate-in-conversation.md) — follow-up iterations with `conversation_id`
