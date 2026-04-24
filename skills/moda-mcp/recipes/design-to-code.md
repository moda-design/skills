# Design to code

**Problem:** The user has a Moda canvas (a share link or a private URL) and wants it implemented as working code. Example: _"Implement the app wireframes from this Moda canvas [URL] in React with Tailwind."_

## Primitives

- `list_moda_canvas_pages` — discover multi-page structure
- `get_moda_canvas` — fetch semantic pseudo-HTML per page
- `get_moda_canvas_tokens` — extract design tokens for theme config
- `export_canvas(format="png")` — optional visual reference for tricky layouts

## Agent-chat sketch

**User:** "Implement the app wireframes from this Moda canvas in React with Tailwind: `https://moda.app/s/abc123`"

**Agent** (discover structure):

```
pages = list_moda_canvas_pages(url="https://moda.app/s/abc123")
# { canvas_name: "App Wireframes", total_pages: 4,
#   pages: [ { page_number: 1, name: "Login", ... }, { page_number: 2, name: "Dashboard", ... }, ... ] }
```

Agent (to user):

> Found a 4-page canvas: "Login," "Dashboard," "Settings," "Profile." I'll implement each as a separate React component with shared Tailwind theme. Extracting tokens first, then walking page by page.

**Extract tokens for the theme:**

```
tokens = get_moda_canvas_tokens(url="https://moda.app/s/abc123")
# { variables: { primary: "#2563eb", ... },
#   colors: [ ... ], fonts: [ { family: "Inter", weights: [400, 700], roles: ["body", "heading"] } ],
#   radii: [ "8px", "16px" ], dimensions: { width: 1440, height: 900 } }
```

Generate `tailwind.config.ts` from `tokens.colors`, `tokens.fonts`, `tokens.radii`, and `tokens.variables`.

**Walk pages:**

```
for page in pages["pages"]:
    html = get_moda_canvas(url="https://moda.app/s/abc123", page_number=page["page_number"])
    # Emit app/(auth)/<page.name>.tsx or similar
    # Translate the semantic tags directly:
    #   <Card> → <Card> (shared component) or <div className="rounded-2xl bg-white ...">
    #   <Heading font-size="32px" font-weight="700" color="#111827">
    #     → <h1 className="text-[32px] font-bold text-[#111827]">
    #   <TextInput border="1px solid #d1d5db" ...>
    #     → <input className="border border-[#d1d5db] rounded-lg ..." />
```

Agent (to user):

> Done. I generated `tailwind.config.ts` from the canvas tokens and one component per page:
> - `app/login/page.tsx`
> - `app/dashboard/page.tsx`
> - `app/settings/page.tsx`
> - `app/profile/page.tsx`
>
> The Moda semantic tags (Card, Heading, TextInput, Button) map to shared components in `components/ui/`. Let me know if you want a different project structure.

## When the structured data isn't enough

For designs with overlapping layers, complex gradients, or precise visual spacing that pseudo-HTML doesn't capture:

```
png = export_canvas(url="https://moda.app/s/abc123", format="png", page_number=1)
# pair the PNG with the HTML in the code-generation prompt:
#   "Here's the structured layout and a visual reference — match both."
```

Signed URL expires after 7 days.

## Tell the user to name their layers

If the pseudo-HTML comes back full of `<Box>` and `<Rectangle>` instead of semantic tags like `<Button>` and `<Card>`, the source canvas has unnamed layers. Point the user at [docs.moda.app/mcp/naming-layers](https://docs.moda.app/mcp/naming-layers) — even renaming a few key layers dramatically improves output.

## Gotchas

- **Multi-page canvases get expensive if you omit `page_number`.** All pages concatenate into a single response. For 10+ pages, walk them.
- **Layer names > visual heuristics.** A `cta-button` layer becomes `<Button>`; an unnamed dark rectangle might too by heuristic but don't bet on it.
- **Design tokens in Moda's variables panel carry their names forward.** Named variables map 1:1 to CSS custom properties / Tailwind theme keys — use them.
- **Share links work unauthenticated.** Private canvas URLs (`moda.app/canvas/…`) require auth.
- **Don't re-fetch the same canvas every turn.** Cache the HTML in your own context — it doesn't change unless the user edits the source canvas.

## Variant: design system from a single canvas

Some users put an entire component library on one canvas (buttons, cards, text styles, etc.). For those:

```
html = get_moda_canvas(url=canvas_url)
# Generate one Storybook story per semantic element:
#   <Button> → stories/Button.stories.tsx
#   <Card> → stories/Card.stories.tsx
```

## Variant: pixel-perfect implementation

For "implement this pixel-perfect in React," pair `get_moda_canvas` with `export_canvas(format="png")`. Tell the code model to use exact hex colors, font sizes, and spacing from the pseudo-HTML — don't round to Tailwind's default scale unless the user says so.

## See also

- [`../references/design-to-code.md`](../references/design-to-code.md) — semantic tag table, URL formats
- [`../references/tools.md`](../references/tools.md#get_moda_canvas) — tool reference
- [`docs.moda.app/mcp/design-to-code`](https://docs.moda.app/mcp/design-to-code) — upstream best practices
- [`docs.moda.app/mcp/naming-layers`](https://docs.moda.app/mcp/naming-layers) — layer-naming keyword reference
