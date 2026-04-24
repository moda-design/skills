# Onboard a new brand

**Problem:** First-run on a fresh team — no brand kit exists yet, and the user is about to run their first design. You need to set up a brand kit before the first task, or explicitly confirm they want to skip brand styling.

## Primitives

- `list_brand_kits` — check what exists
- `create_brand_kit` — extract from a website URL (10–30s)
- `start_design_task` — run the first design with the new kit

## Agent-chat sketch

**User:** "Make me a LinkedIn post for our new product launch."

**Agent** (runs the gate, hits the brand-kit check):

```
kits = list_brand_kits()
# { brand_kits: [], team_id: "…" }   ← empty
```

**Agent** (to user, before the design task):

> I don't see a brand kit for this team yet. Two options:
>
> 1. **Set up a brand kit from your website** — I can extract your colors, fonts, logos, and tone automatically. What's your company URL?
> 2. **Skip brand styling for this one design** — I'll use neutral defaults. You can set up a brand kit later.

**User:** "Yeah, extract from acme.com"

**Agent** (create the kit — takes 10–30s):

```
kit = create_brand_kit(url="acme.com")
# {
#   id: "bk_01HT9…", title: "Acme Corp", is_default: true,
#   company_name: "Acme Corp", company_url: "https://acme.com",
#   colors: [ { color: "#2563eb", label: "Primary" }, ... ],
#   fonts: [ { family: "Inter", label: "Body", weight: 400, supported: true }, ... ],
#   logos: [ { group_name: "Primary Logo", images: [ { name: "logo-dark.svg", url: "…" } ] } ],
#   ...
# }
```

Agent (to user):

> Set up the "Acme Corp" brand kit from acme.com — extracted your brand colors, Inter as the body font, and your logo. It's set as your default and will apply to every design from now on. Kicking off the LinkedIn post now (2–10 min).

**Agent** (run the design):

```
task = start_design_task(
  prompt="LinkedIn post announcing our new product launch — <product details>",
  format_category="social",
  format_width=1080,
  format_height=1080,
  # brand_kit_id omitted — default applies automatically
)
# poll and deliver as usual
```

## Variant: user skips the brand kit

**User:** "Skip it for now."

**Agent** (to user):

> OK, I'll use neutral styling for this one — you can set up a brand kit later by saying "create a brand kit from <url>". Running the design now.

```
task = start_design_task(
  prompt="...",
  format_category="social",
  skip_brand_kit=True,                    # opt out explicitly
)
```

## Variant: user names a specific brand (not theirs) to emulate

If the user says "use Stripe's brand for this one":

```
stripe_kit = create_brand_kit(url="stripe.com")
# stripe_kit.is_default will be True iff this is still their first kit.
# If they already have a kit, stripe_kit.is_default is False.

task = start_design_task(
  prompt="...",
  brand_kit_id=stripe_kit["id"],
)
```

After this, the user has two kits in their team — their own (still default, if created first) and Stripe's (on-demand for this one task).

## Post-creation UX

Every brand kit's first-use should tell the user what got extracted, so they can spot obvious errors:

> Extracted:
> - **Primary colors:** #2563eb (primary), #0a2540 (dark), ...
> - **Fonts:** Inter (body + heading)
> - **Logos:** 2 logos (dark + light variants)
> - **Voice:** professional, friendly
>
> Want to tweak any of this? I can update the kit with `update_brand_kit`.

## Gotchas

- **`create_brand_kit` takes 10–30s.** It scrapes the website via Firecrawl. Don't call it in a polling loop — one call per URL.
- **First kit per team becomes default automatically.** Every subsequent kit is non-default unless `update_brand_kit` changes it (server-side; there's no explicit field in the public API — the user changes defaults in the app UI today).
- **Don't infer a brand from the prompt.** "Make a deck for Acme Corp" does **not** mean "use Acme Corp's brand." It probably means the user's brand, with Acme as the audience. Ask.
- **Cached extraction.** Re-calling `create_brand_kit` for the same URL returns a cached result quickly — safe to re-run if the first call surprised you.
- **Don't skip the brand kit silently.** If `list_brand_kits` is empty and you proceed without asking, the design will come back off-brand and the user will be annoyed. Always surface the choice.

## See also

- [`../references/brand-kits.md`](../references/brand-kits.md) — tool reference, update semantics, array-replacement rule
- [`../SKILL.md`](../SKILL.md) — gate 6 (brand check)
- [`brief-to-deck.md`](./brief-to-deck.md) — the canonical first-design flow once the kit exists
