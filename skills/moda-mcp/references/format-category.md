# format_category

`format_category` tells Moda what kind of thing the user is making. Passing the wrong value — or omitting it on a non-slide design — is the single biggest cause of "wrong output" complaints.

## The seven values

| Value | What it's for | Typical dimensions |
| --- | --- | --- |
| `slides` | Slide decks, presentations, pitch decks | 1920×1080 (16:9) |
| `social` | Single-image social posts, banner ads | 1080×1080 (IG square), 1080×1920 (IG story), 1200×628 (LinkedIn banner) |
| `carousel` | Instagram / LinkedIn carousel posts — multiple linked images | `carousel_dimensions` + `carousel_page_count` |
| `pdf` | Reports, resumes, one-pagers, documents | 8.5×11" or A4 |
| `diagram` | Flowcharts, org charts, process diagrams | Usually square or landscape |
| `ui` | UI mockups, screens, wireframes | 1440×900 or 1280×800 (desktop), 390×844 (mobile) |
| `other` | Anything else (posters, infographics, maps, etc.) | Specify `format_width` / `format_height` |

## Mapping user language to values

| User says | `format_category` | Also set |
| --- | --- | --- |
| "pitch deck", "slide deck", "presentation", "slides" | `slides` | `format_width=1920`, `format_height=1080`; state slide count in the prompt ("N slides") |
| "Instagram post", "LinkedIn post" (single image), "Twitter post", "banner ad" | `social` | `format_width` + `format_height` per platform |
| "Instagram carousel", "LinkedIn carousel", "5-slide IG post" | `carousel` | `carousel_dimensions` + `carousel_page_count` (≤ 5) |
| "report", "resume", "one-pager", "PDF", "document" | `pdf` | |
| "flowchart", "diagram", "org chart", "process map" | `diagram` | |
| "UI mockup", "login screen", "app screen", "wireframe" | `ui` | `format_width` + `format_height` |
| "poster", "infographic", "custom thing" | `other` | `format_width` + `format_height` |

## Carousel controls

When `format_category="carousel"`:

| Parameter | Values | What it means |
| --- | --- | --- |
| `carousel_dimensions` | `square` | 1080×1080 — Instagram carousel |
| `carousel_dimensions` | `linkedin` | 1080×1350 — LinkedIn portrait carousel |
| `carousel_dimensions` | `portrait` | 1080×1920 — Instagram story / vertical |
| `carousel_page_count` | integer, 1–5 | Number of panels. **Hard cap at 5** per product constraint. |

If the user asks for "10 Instagram carousel slides," that exceeds the cap. Options:

1. Push back: "Instagram carousels cap at 5 slides. Do you want 5 carousel panels, or 10 separate posts as individual social designs?"
2. If they want 10 standalone posts, fan out 10 `start_design_task` calls with `format_category="social"` and `carousel_page_count` omitted.

## Default dimensions per category

If you omit `format_width` / `format_height`, Moda picks a sensible default based on `format_category`. But default values vary over time — **explicit dimensions** give you predictable output. Always pass them for social and carousel (platform-specific) and for custom sizes.

## Worked examples

### Wrong

```
# User asked for an Instagram post. This produces a slide deck.
start_design_task(prompt="Instagram post announcing our summer sale")
```

```
# User asked for a carousel. This produces a single static IG post.
start_design_task(
  prompt="5-panel Instagram carousel for our summer sale",
  format_category="social",
)
```

```
# 10 panels exceeds the cap.
start_design_task(
  prompt="10-slide LinkedIn carousel about remote work",
  format_category="carousel",
  carousel_page_count=10,  # cap is 5
)
```

### Right

```
start_design_task(
  prompt="Instagram post announcing our summer sale — 20% off everything",
  format_category="social",
  format_width=1080,
  format_height=1080,
)
```

```
start_design_task(
  prompt="5-panel Instagram carousel for our summer sale",
  format_category="carousel",
  carousel_dimensions="square",
  carousel_page_count=5,
)
```

```
start_design_task(
  prompt="One-page project status report",
  format_category="pdf",
)
```

```
start_design_task(
  prompt="Login screen mockup for a mobile banking app",
  format_category="ui",
  format_width=390,
  format_height=844,
)
```

## Model tier + `skip_brand_kit` note

For the **Pro** and **Ultra** plans, `model_tier="pro"` produces more sophisticated design decisions than `standard` or `lite`. It's worth paying the extra latency on high-stakes work (investor decks, customer-facing materials). `lite` is the fastest. If you omit `model_tier`, Moda picks based on task complexity.

The legacy `model_tier="pro_max"` is silently coerced to `pro`. Don't document or pass `pro_max`.

If the user wants a deliberately off-brand design and no brand kit applies, pass `skip_brand_kit=True`. The server may also pick a stronger model tier automatically when `skip_brand_kit=True` to compensate for the lack of brand anchors.

## Common wrong guesses

- **Omitting `format_category` on a non-slide design.** Default is slides. Always pass `format_category` explicitly for social, carousel, pdf, diagram, ui, or other.
- **Using `format_category="social"` for a carousel.** Carousel is its own value with its own controls.
- **Passing `carousel_page_count > 5`.** Product cap is 5.
- **Setting `format_width` / `format_height` without `format_category`.** Dimensions alone don't tell the agent the layout intent.
- **Passing `carousel_dimensions` without `format_category="carousel"`.** The server ignores it.
- **Using `pro_max`.** Silently coerced to `pro`. Pass `pro` directly.

## Upstream

- [`docs.moda.app/mcp/tools#start_design_task`](https://docs.moda.app/mcp/tools#start_design_task) — parameter reference
- [`docs.moda.app/help/ai-agent/prompting`](https://docs.moda.app/help/ai-agent/prompting) — format-specific prompt templates
