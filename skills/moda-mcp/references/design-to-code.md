# Design-to-code

Moda provides three tools for turning an existing canvas into production code: `get_moda_canvas`, `get_moda_canvas_tokens`, and `list_moda_canvas_pages`. `export_canvas` (format=`png`) complements them when the structured data needs a visual reference.

## The primary tool

`get_moda_canvas(url=…)` returns **semantic pseudo-HTML with CSS properties** plus a design-tokens summary. Example:

```html
## Page: Login Screen (1440x900) [page 1]

<section background="#f3f4f6" height="900px" width="1440px" display="flex" justify-content="center" align-items="center">
  <Card background="#ffffff" border-radius="16px" width="600px" display="flex" flex-direction="column" gap="20px">
    <Heading font-size="32px" font-weight="700" color="#111827">Welcome back</Heading>
    <Text font-size="14px" color="#6b7280">Sign in to your account</Text>
    <TextInput border="1px solid #d1d5db" border-radius="8px" height="48px" width="520px" />
    <button background="#2563eb" border-radius="8px" height="48px" width="520px">Sign in</button>
  </Card>
</section>

## Design Tokens — Colors: #111827, #2563eb, #6b7280, #d1d5db, #f3f4f6, #ffffff — Font Inter: weights [400, 700] roles [body, heading] — Corner radii: 8px, 16px
```

The tag names (`Heading`, `Card`, `Button`, `TextInput`) are semantic, not visual. That's what makes output accurate enough to translate directly to React, Vue, HTML, SwiftUI, or any other framework.

## URL formats accepted

| Format | Example |
| --- | --- |
| Share link | `https://moda.app/s/abc123-token` |
| Private canvas URL | `https://moda.app/canvas/550e8400-…` |
| Raw share token | `abc123-token` |
| Legacy domain | `https://app.moda.so/s/abc123-token` |

Private canvas URLs require auth. Share links work on the remote server without auth.

## Multi-page flow

Before `get_moda_canvas` on an unknown design, call `list_moda_canvas_pages(url=…)`:

```json
{
  "canvas_name": "Marketing Website",
  "total_pages": 3,
  "pages": [
    { "page_number": 1, "name": "Hero Section", "width": 1440, "height": 900, "node_count": 12 },
    { "page_number": 2, "name": "Features", "width": 1440, "height": 1200, "node_count": 24 },
    { "page_number": 3, "name": "Pricing", "width": 1440, "height": 900, "node_count": 18 }
  ]
}
```

Then fetch each page separately:

```
for page in pages:
    html = get_moda_canvas(url=..., page_number=page["page_number"])
    generate_component(page["name"], html)
```

Omitting `page_number` returns all pages concatenated — fine for small designs, expensive for large multi-page ones.

## Tokens-only

`get_moda_canvas_tokens(url=…)` returns structured JSON of colors, fonts, variables, and radii. Use it when generating theme config (Tailwind, Chakra, CSS custom properties) without the full layout:

```json
{
  "variables": { "primary": "#2563eb", "background": "#f3f4f6" },
  "colors": ["#111827", "#2563eb", "#6b7280", "#d1d5db", "#f3f4f6", "#ffffff"],
  "fonts": [{ "family": "Inter", "weights": [400, 700], "roles": ["body", "heading"] }],
  "radii": ["8px", "16px"],
  "dimensions": { "width": 1440, "height": 900 }
}
```

Variables defined in Moda's variables panel appear in `variables` with their names — they map naturally to CSS custom properties.

## Semantic tag reference

The transformer assigns tags from a small vocabulary based on visual properties + layer names:

| Tag | When |
| --- | --- |
| `Heading` | Text with font-size ≥ 24px or font-weight ≥ 600 |
| `Text` | Default text |
| `Button` | Rectangle with text, dark fill, button-like dimensions |
| `TextInput` | Rectangle with light fill, thin border, no text |
| `Image` | Element with an image fill |
| `Avatar` | Small circular element with an image fill |
| `Card` | Group with a background rectangle and content |
| `Row` / `Column` | Container with `flex-direction: row` / `column` |
| `Divider` | Line element |
| `Nav` / `Hero` / `Footer` / `Section` / `Modal` / `Sidebar` / `Banner` / `Tag` / `Badge` / `Icon` / `List` / `Table` / `Checkbox` / `Radio` / `Toggle` / `Select` / `Link` | Matched from layer names |

**Layer names take priority over visual heuristics.** A rectangle named `cta-button` becomes `<Button>`; an unnamed dark rectangle with text might also become a button by heuristic. Explicit names win when they disagree.

Full keyword reference: [`docs.moda.app/mcp/naming-layers`](https://docs.moda.app/mcp/naming-layers).

## When to combine with `export_canvas`

Pseudo-HTML doesn't capture everything — overlapping elements, complex gradients, subtle visual spacing. For those, pair with a PNG export:

```
html = get_moda_canvas(url=..., page_number=1)
png  = export_canvas(url=..., format="png", page_number=1)
# pass both to the code generator: structured data + visual reference
```

The signed URL from `export_canvas` expires after 7 days — fetch it promptly.

## Worked patterns

### React + Tailwind from a share link

```
html = get_moda_canvas(url="https://moda.app/s/abc123")
# then prompt the code model:
#   "Convert this pseudo-HTML to a React component using Tailwind CSS.
#    Preserve the semantic tag names as component names."
```

### Theme config for a component library

```
tokens = get_moda_canvas_tokens(url="https://moda.app/s/abc123")
# generate tailwind.config.ts from tokens.colors, tokens.fonts, tokens.radii
```

### Multi-page Next.js site

```
pages = list_moda_canvas_pages(url="https://moda.app/s/abc123")
for page in pages["pages"]:
    html = get_moda_canvas(url="https://moda.app/s/abc123", page_number=page["page_number"])
    # emit app/{page.name}/page.tsx
```

### Component library from a canvas

```
# each Moda page = one component story
pages = list_moda_canvas_pages(url="…")
for page in pages["pages"]:
    html = get_moda_canvas(url="…", page_number=page["page_number"])
    # emit a Storybook story file per component
```

## Prompting tips for better output

Tell the user to:

- **Name their layers.** A rectangle named `cta-button` becomes `<Button>`; an unnamed rectangle might be `<Box>`.
- **Use Moda's auto-layout (flex).** The transformer detects flex layouts and emits `display: flex` with `gap` — maps directly to CSS.
- **Group related elements.** Groups become semantic containers.
- **Use design variables in Moda.** Named variables show up in the tokens output with their names, making theme extraction trivial.

## Common wrong guesses

- **Using `get_moda_canvas` on a multi-page design without calling `list_moda_canvas_pages` first.** You'll get all pages concatenated — big and expensive to process.
- **Parsing the tokens summary from the `get_moda_canvas` output instead of calling `get_moda_canvas_tokens`.** The dedicated tokens tool returns structured JSON; regex against the HTML output is fragile.
- **Ignoring layer names.** The transformer uses them. If the generated code says `<Box>` everywhere, the source canvas has unnamed layers.
- **Re-fetching share links you've already read this session.** Cache the HTML in your own context.
- **Letting a PNG export URL expire.** Signed URLs live 7 days; don't persist them longer.

## Upstream

- [`docs.moda.app/mcp/design-to-code`](https://docs.moda.app/mcp/design-to-code) — best practices
- [`docs.moda.app/mcp/naming-layers`](https://docs.moda.app/mcp/naming-layers) — full keyword reference
- [`docs.moda.app/mcp/tools#get_moda_canvas`](https://docs.moda.app/mcp/tools#get_moda_canvas)
