# Brand kits

A brand kit is a stored bundle of colors, fonts, logos, tagline, voice, values, and aesthetic descriptors. When a design task runs, Moda's design agent applies the team's default brand kit automatically unless you opt out.

## The tools

- **`list_brand_kits`** — list all kits for the active team. The one with `is_default: true` is what `start_design_task` will use if no `brand_kit_id` is passed.
- **`create_brand_kit(url=…)`** — extract brand data from a company website. Takes 10–30 seconds (Firecrawl-backed). Cached on subsequent runs for the same URL.
- **`update_brand_kit(brand_kit_id=…, …)`** — partial update. Pass only the fields you want to change. When updating `colors` or `fonts`, the entire array is replaced (not merged).
- **`set_default_brand_kit(brand_kit_id=…)`** — promote a kit to the team default; clears the previous default. Destructive — only on explicit user ask.
- **`delete_brand_kit(brand_kit_id=…)`** — soft-delete. Destructive — only call when the user names the specific kit to delete.
- **`list_brand_kit_images` / `add_brand_kit_image` / `remove_brand_kit_image`** — manage logos and reference images inside a kit. `add` takes a `file_id` from `upload_file` and a role (`logo` / `reference` / `asset`).

## The default-kit rule

The first brand kit created for a team becomes the default automatically. `start_design_task` with no `brand_kit_id` uses the default. There is always at most one default per team.

Three ways to control branding on a single task:

| Intent | How |
| --- | --- |
| Use the team's default | Pass nothing. The default applies. |
| Use a specific kit | Pass `brand_kit_id` explicitly. |
| Skip brand styling entirely | Pass `skip_brand_kit=True`. Overrides `brand_kit_id` if both are set. |

## The onboarding flow (first-run)

Run this before the first `start_design_task` call on a fresh team:

```
kits = list_brand_kits()
if not kits["brand_kits"]:
    # No kit yet. Offer to create one or skip.
    ask_user: "I can create a brand kit from your website — what's the URL?
               Or say 'skip' to design without brand styling."
    if url_given:
        kit = create_brand_kit(url="https://acme.com")
        # becomes default automatically
    else:
        # user will pass skip_brand_kit=True on each start_design_task call
```

After this, every subsequent design uses the kit without the user having to mention it.

## The list response

```json
{
  "brand_kits": [
    {
      "id": "880e8400-…",
      "title": "Acme Corp",
      "is_default": true,
      "company_name": "Acme Corp",
      "company_url": "https://acme.com",
      "company_description": "…",
      "tagline": "Design at scale",
      "brand_values": ["innovation", "simplicity"],
      "brand_aesthetic": ["modern", "minimal"],
      "brand_tone_of_voice": ["professional", "friendly"],
      "colors": [{ "color": "#2563eb", "label": "Primary" }, …],
      "fonts": [{ "family": "Inter", "label": "Body", "weight": 400, "supported": true }, …],
      "logos": [{ "group_name": "Primary Logo", "images": [{ "name": "logo-dark.svg", "url": "…" }] }, …]
    }
  ],
  "team_id": "660e8400-…"
}
```

## Updates

Partial update. Omitted fields are not touched. Array fields (`colors`, `fonts`, `brand_values`, `brand_aesthetic`, `brand_tone_of_voice`) are **replaced wholesale** when you pass them — not merged. If you want to add one color to a kit, read the existing array, append your color, and pass the whole list back.

```
current = list_brand_kits()["brand_kits"][0]
update_brand_kit(
  brand_kit_id=current["id"],
  colors=[*current["colors"], {"color": "#ff6b35", "label": "Accent"}],
)
```

## Design-agent behavior

When a brand kit is applied:

- The agent uses the kit's colors and fonts across the canvas.
- The agent follows `brand_aesthetic` and `brand_tone_of_voice` when making style + copy decisions.
- Logos from the kit are dropped in where appropriate (first slide, footer, etc.).
- The agent does **not** regurgitate `brand_values` or `tagline` into the design as literal text unless the prompt asks for it.

Tell the user which kit you used in your follow-up message ("I applied your default brand kit, Acme Corp").

## Prompting around brand

- Don't repeat brand colors / fonts / logos in the prompt when the kit already has them — it's noise.
- If the user wants something *off-brand* (e.g. a fun internal card), pass `skip_brand_kit=True` and say so in the prompt: "Casual internal birthday card, off-brand."
- If the user wants a specific non-default kit, name it in the prompt *and* pass the `brand_kit_id` — the name in the prompt gives the user confidence you picked the right one.

## Common wrong guesses

- **Pasting brand colors and logo URLs into the prompt** when the brand kit already has them. Redundant; sometimes overrides the kit.
- **Forgetting `skip_brand_kit=True`** when the user wants an explicitly off-brand design. The default kit will apply and skew the output.
- **Merging array updates in your head** and only passing the new entries. `colors` / `fonts` etc. are **replaced**; include the full list.
- **Calling `create_brand_kit` and expecting it in < 5s.** It scrapes the website; budget 10–30s.
- **Treating `is_default: true` as a field you can set via `update_brand_kit`.** It's not in `update_brand_kit`'s field list — use the dedicated `set_default_brand_kit(brand_kit_id=…)` tool to promote a kit, or the in-app UI.

## Upstream

- [`docs.moda.app/mcp/tools#list_brand_kits`](https://docs.moda.app/mcp/tools#list_brand_kits)
- [`docs.moda.app/mcp/tools#create_brand_kit`](https://docs.moda.app/mcp/tools#create_brand_kit)
- [`docs.moda.app/mcp/tools#update_brand_kit`](https://docs.moda.app/mcp/tools#update_brand_kit)
- [`docs.moda.app/help/brand-kit/setup`](https://docs.moda.app/help/brand-kit/setup) — user-facing brand-kit guide
