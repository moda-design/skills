# Customize a template for a prospect

**Problem:** The user wants a prospect-specific follow-up deck built from their call notes, using an existing sales template as the style anchor. Example: _"Take the attached call notes and create a follow-up deck for this prospect using our sales template. Include their goals, pain points, our recommended solution, and next steps."_

## Primitives

- `upload_file` — bring the call notes (PDF or DOCX) into Moda
- `search_canvases` — find the sales template
- `start_design_task` — kick off the design with source + reference attachments
- `get_task_status` — poll to completion
- `export_canvas` (optional) — deliver as PDF or PPTX

## Agent-chat sketch

**User:** "Here are my call notes from the Acme Corp pitch — [attaches PDF]. Build a follow-up deck for them using our sales template."

**Agent** (runs the prompt-gathering gate — most gates are answered; a couple need confirming):

> A few quick confirmations before I start (this takes 2–10 minutes):
> - I'll pull content from the call-notes PDF and match the style of your sales template. Which template — "Sales Deck 2026" or "Enterprise Pitch"?
> - I'll use your default brand kit "Acme Corp" unless you'd prefer something else.
> - How many slides? I'll plan for 8 unless you want more or fewer.

**User:** "Sales Deck 2026, 10 slides is fine."

**Agent** (tool calls):

```
notes     = upload_file(source_url="<PDF URL from the chat attachment>")
templates = search_canvases(query="Sales Deck 2026", limit=5)
template_id = templates[0]["id"]                            # pick the first match or disambiguate

task = start_design_task(
  prompt="""
    Build a follow-up deck for Acme Corp based on the attached call notes.
    Structure:
      1. Title slide — Acme Corp follow-up
      2. Recap of goals (from call notes)
      3. Pain points we heard
      4. Recommended solution
      5. How it maps to Acme's goals
      6. Case study / social proof
      7. Proposed rollout plan
      8. Investment + next steps
      9. Team + contacts
      10. Close

    Match the visual style of the referenced sales template. Use concrete details from the notes —
    names, dates, metrics — but do not invent specifics that aren't in the notes.
  """,
  format_category="slides",
  format_width=1920,
  format_height=1080,
  attachments=[
    { "file_id": notes["id"], "role": "source", "label": "Acme call notes" },
  ],
  reference_canvas_ids=[template_id],
)
```

**Agent** (poll):

```
status = get_task_status(task_id=task["task_id"])
while not status["is_terminal"]:
    sleep(status["retry_after_seconds"])
    status = get_task_status(task_id=task["task_id"])
```

**Agent** (delivery):

> Done — follow-up deck for Acme Corp: `<canvas_url>`. Want a PPTX export to send them?

## Gotchas

- **`role: "source"` on the notes, `reference_canvas_ids` on the template.** Don't paste the template as an attachment — canvas references are first-class and give the agent full structure access.
- **Resolve the template with `search_canvases` first.** Don't hard-code IDs; template names may not match exactly.
- **Ask when the match is ambiguous.** If `search_canvases` returns multiple hits, show the user the names and ask which one.
- **Pin content truthfulness.** The prompt should tell the agent to use specifics from the notes and **not invent** — agents are otherwise happy to fabricate quotes and metrics.
- **One brand kit.** If Acme Corp is the prospect (not the user), you're still styling with the user's brand kit — use `skip_brand_kit=True` only if the user wants an off-brand deck.

## See also

- [`../references/attachments.md`](../references/attachments.md) — role semantics (source / reference / asset) + `reference_canvas_ids`
- [`../SKILL.md`](../SKILL.md) — prompt-gathering gate
- [`pull-existing-canvas.md`](./pull-existing-canvas.md) — when the user wants to edit the template in place
