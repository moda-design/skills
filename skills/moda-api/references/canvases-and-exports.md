# Canvases and exports

All canvas-shaped read + export flows live under `/v1/canvases` and `/v1/remix`. Plus the share-token read pattern for public canvases and the `/v1/share_links/resolve` helper.

## Endpoints

| Verb | Path | Scope |
| --- | --- | --- |
| GET | `/canvases` | `canvases:read` |
| GET | `/canvases/search` | `canvases:read` |
| GET | `/canvases/{id}` | `designs:read` |
| GET | `/canvases/{id}/tokens` | `designs:read` |
| GET | `/canvases/{id}/pages` | `designs:read` |
| POST | `/canvases/{id}/export` | `designs:export` |
| POST | `/canvases/{id}/share` | `canvases:write` |
| POST | `/remix` | `tasks:write` |
| POST | `/share_links/resolve` | (public) |

## Listing and search

```
GET /v1/canvases?limit=100
GET /v1/canvases/search?query=summer+launch&limit=50
```

Cursor-paginated (`{data, next_cursor}`). Sort is `(created_at DESC, id DESC)`. See [`pagination.md`](./pagination.md).

List items include `id`, `name`, `url`, `category`, `visibility`, `created_at`, `updated_at`.

## Reading a canvas

```
GET /v1/canvases/{id}
```

Returns the canvas as semantic pseudo-HTML with CSS properties + embedded design tokens. Same format as MCP's `get_moda_canvas`. Requires team access.

### Reading a public share

```
GET /v1/canvases/{id}?share_token=<token>
```

Share-token-authenticated callers can read the canvas (view / view_remix permission) without team access. Use in combination with `POST /v1/share_links/resolve` to parse a share URL first:

```
POST /v1/share_links/resolve
{ "url": "https://moda.app/s/abc123" }
→ { "canvas_id": "cvs_…", "share_token": "abc123", "permission": "view_remix", "expires_at": null }
```

Share-link-only callers can read but **cannot export** (see below).

### Tokens only

```
GET /v1/canvases/{id}/tokens
```

Returns `{variables, colors, fonts, radii, dimensions}` — fast path for theme regeneration in CI.

### Pages metadata

```
GET /v1/canvases/{id}/pages
```

Returns `{canvas_name, total_pages, pages: [{page_number, name, width, height, node_count}]}`. Call before `GET /v1/canvases/{id}?page_number=N` on multi-page canvases to plan per-page fetches.

## Export — **synchronous**

```
POST /v1/canvases/{id}/export?format=pptx
```

Query parameters:

| Param | Values | Default |
| --- | --- | --- |
| `format` | `png` / `jpeg` / `pdf` / `pptx` | `png` |
| `page_number` | integer ≥ 1 | all pages for documents, page 1 for images |
| `pixel_ratio` | 1–4 | server default |
| `flatten` | bool (PDF only — raster-only no text) | `true` |

Returns immediately:

```json
{ "url": "https://storage.googleapis.com/.../deck.pptx", "format": "pptx" }
```

**The URL expires after 7 days.** Download promptly.

Scope: `designs:export` **and** team membership. Share-token-only callers (no team access) cannot export — reads via `share_token` are not enough.

### Export when a design task is running

If the target canvas has an in-flight design task, export returns:

```
HTTP/1.1 409 Conflict
Retry-After: 10
Content-Type: application/json

{
  "error": {
    "type": "conflict",
    "code": "canvas_active_job",
    "message": "Canvas cvs_… has an active design task; retry after it completes.",
    "request_id": "019d8996-…"
  }
}
```

Back off for `Retry-After` seconds and retry. This is expected behavior in pipelines that chain a task → export — either pass through the wait, or (better) let the task's webhook trigger the export.

### Export is NOT a Task

Unlike design / remix / brand-kit extraction, exports don't return a Task envelope today. The `export` kind exists in webhook event types (for future async export flows), but `POST /v1/canvases/{id}/export` itself is inline. Don't poll `/v1/tasks/{id}` for an export.

## Sharing — blocking thumbnail default

```
POST /v1/canvases/{id}/share
{ "wait_for_thumbnail": true }     // default
```

Returns the share URL + share token. **By default, this call blocks until a thumbnail is generated** so the URL unfurls properly on social media / Slack. Thumbnail generation usually takes a few seconds; pass `wait_for_thumbnail: false` to skip if you don't care about unfurls.

## Remix

```
POST /v1/remix
{
  "canvas_id": "cvs_01HT9...",
  "prompt": "Change to dark mode",          // optional
  "new_name": "Q2 Deck (dark)",             // optional
  "brand_kit_id": "bk_01HT9..."             // optional, only used with a prompt
}
```

Returns a Task envelope (`kind: "remix"`). Without a `prompt`: the task is synchronous, returns `status: "succeeded"` inline, `result.canvas_id` is the new canvas. With a prompt: queues a design task on the copy, returns non-terminal; poll same as `/tasks/{id}`.

The source canvas is **never** modified.

## Design-to-code walk

```
# Discover structure
pages = GET /v1/canvases/{id}/pages
# → { total_pages: N, pages: [ { page_number, name, width, height, node_count } ] }

# Extract tokens for theme
tokens = GET /v1/canvases/{id}/tokens
# → { variables, colors, fonts, radii, dimensions }

# Walk pages
for page in pages.pages:
    html = GET /v1/canvases/{id}?page_number={page.page_number}
    # → pseudo-HTML + embedded tokens
```

For visual reference on complex layouts, pair with `POST /v1/canvases/{id}/export?format=png`.

## Common wrong guesses

- **Expecting `POST /v1/canvases/{id}/export` to return a Task envelope.** Synchronous; returns `{url, format}` inline.
- **Treating the `409 canvas_active_job` response as a bug.** It's the intended retry signal when chaining task → export.
- **Ignoring `Retry-After` on the 409 response.** Back off the suggested seconds; don't hammer.
- **Using `share_token=` to export.** Only reads are permitted via share token. Export requires team access.
- **Skipping `wait_for_thumbnail: false` on `/share` calls in a script.** By default it blocks — in a batch share-link generator, the latency adds up. Pass `false` if you don't care about unfurls.
- **Treating `GET /v1/canvases/{id}` without `page_number` as cheap on multi-page designs.** It returns all pages concatenated.
- **Holding an export URL longer than 7 days.** Expires. Re-export if needed.
- **Storing the `X-Request-ID` header from a successful export** to use as an idempotency key. That's what the body-field `idempotency_key` on `POST /v1/tasks` is for — exports don't need it (stateless + fast).

## Upstream

- [`docs.moda.app/api/canvases/listCanvases`](https://docs.moda.app/api/canvases/listCanvases)
- [`docs.moda.app/api/canvases/getCanvas`](https://docs.moda.app/api/canvases/getCanvas)
- [`docs.moda.app/api/canvases/exportCanvas`](https://docs.moda.app/api/canvases/exportCanvas)
- [`docs.moda.app/api/canvases/makeCanvasPublic`](https://docs.moda.app/api/canvases/makeCanvasPublic)
- [`docs.moda.app/api/remix/remixCanvas`](https://docs.moda.app/api/remix/remixCanvas)
- [`docs.moda.app/api/share-links/resolveShareLink`](https://docs.moda.app/api/share-links/resolveShareLink)
