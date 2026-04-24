# Brand kits (REST)

Full CRUD-ish lifecycle for brand kits. All endpoints under `/v1/brand-kits`.

## Endpoints

| Verb | Path | Scope | Purpose |
| --- | --- | --- | --- |
| GET | `/brand-kits` | `brand_kits:read` | Cursor-paginated list for the key's team |
| POST | `/brand-kits` | `brand_kits:write` | Extract from a URL (Firecrawl) |
| PATCH | `/brand-kits/{id}` | `brand_kits:write` | Partial update |
| DELETE | `/brand-kits/{id}` | `brand_kits:write` | Soft delete; returns `204` |
| POST | `/brand-kits/{id}/images` | `brand_kits:write` | Attach uploaded file as logo / reference / asset |

## Default kit

The **first brand kit created for a team becomes the default automatically.** `POST /v1/tasks` with no `brand_kit_id` uses the default. At most one default per team. The default is server-managed — there is no `is_default` field you can PATCH; the user changes defaults in the Moda app UI.

## List

```
GET /v1/brand-kits?limit=100
```

```json
{
  "data": [
    {
      "id": "bk_01HT9...",
      "title": "Acme Corp",
      "is_default": true,
      "company_name": "Acme Corp",
      "company_url": "https://acme.com",
      "company_description": "…",
      "tagline": "…",
      "brand_values": ["…"],
      "brand_aesthetic": ["…"],
      "brand_tone_of_voice": ["…"],
      "colors": [{ "color": "#2563eb", "label": "Primary" }, …],
      "fonts": [{ "family": "Inter", "label": "Body", "weight": 400, "supported": true }, …],
      "logos": [{ "group_name": "Primary Logo", "images": [{ "name": "logo.svg", "url": "…" }] }],
      "created_at": "2026-…", "updated_at": "2026-…"
    }
  ],
  "next_cursor": "…" | null
}
```

Cursor-paginated; iterate with `?cursor=`. See [`pagination.md`](./pagination.md).

## Create from URL

```
POST /v1/brand-kits
Content-Type: application/json

{"url": "stripe.com"}
```

Server scrapes the URL via Firecrawl and extracts colors, fonts, logos, tone, values, aesthetic. **Takes 10–30 seconds** — a legitimate case for `Prefer: wait=30`:

```
POST /v1/brand-kits
Prefer: wait=30
```

Returns the created brand-kit record (same shape as list items).

URL accepts bare domain (`stripe.com`) or full URL (`https://stripe.com`). Cached — re-calling with the same URL returns the cached result quickly.

If the URL can't be scraped (blocked by robots, 404, login-required): `422 scraping_user_error`.

## Update (partial)

```
PATCH /v1/brand-kits/{id}
Content-Type: application/json

{
  "title": "Acme Corp (Updated)",
  "colors": [
    {"color": "#2563eb", "label": "Primary"},
    {"color": "#0a2540", "label": "Dark"},
    {"color": "#ff6b35", "label": "Accent"}
  ]
}
```

Pass only the fields to change. Omitted fields keep their current values.

**Array fields replace wholesale.** Passing `colors` overwrites the entire array — not a merge. To add one color, fetch the existing array, append, and PATCH the full list:

```python
existing = c.get(f"/brand-kits/{kit_id}").json()            # full record
c.patch(f"/brand-kits/{kit_id}", json={
    "colors": [*existing["colors"], {"color": "#ff6b35", "label": "Accent"}],
})
```

Same rule for `fonts`, `brand_values`, `brand_aesthetic`, `brand_tone_of_voice`.

Returns the updated record.

## Add images (logos / references / assets)

```
POST /v1/brand-kits/{id}/images
Content-Type: application/json

{
  "file_id": "file_01HT9...",
  "role": "logo",         // one of: "logo" | "reference" | "asset"
  "label": "Dark mode logo"
}
```

Requires an existing `file_id` from `POST /v1/uploads`. Attaches the uploaded file to the kit in the named role. Role here is **about the kit** (what this image represents in the brand) — different from the `role` field on task `attachments` (`source` / `reference` / `asset`).

| Role (brand kit) | Meaning |
| --- | --- |
| `logo` | Logo asset (Moda uses it automatically on title slides, footers, etc.) |
| `reference` | Style reference for the design agent |
| `asset` | Miscellaneous asset |

Returns the updated brand-kit record.

## Delete

```
DELETE /v1/brand-kits/{id}
```

Returns `204 No Content`. Soft delete — historical tasks that referenced this kit continue to show it in their audit record. New design tasks with `brand_kit_id` pointing at a deleted kit get `404 not_found`.

If the deleted kit was the team's default, there is no new default automatically. The team operates brand-kit-less until another kit is promoted (in the app UI) or a new kit is created.

## In-task usage

Pass `brand_kit_id` explicitly on `POST /v1/tasks` to override the default:

```json
{ "prompt": "…", "brand_kit_id": "bk_01HT9...", ... }
```

Or `skip_brand_kit: true` to apply no kit:

```json
{ "prompt": "…", "skip_brand_kit": true, ... }
```

`skip_brand_kit` overrides `brand_kit_id` when both are present.

## Common wrong guesses

- **Merging array updates client-side without reading first.** You'll overwrite the kit's colors / fonts with just the new entries. Always read, append, PATCH.
- **Treating `is_default` as writable.** It's server-managed. Default changes happen in the app UI.
- **Using `POST /v1/brand-kits` without `Prefer: wait`** and blocking on the response. The HTTP call returns the completed kit, but it took 10–30s — budget accordingly.
- **Passing `brand_kit_id` for a deleted kit.** `404`. Check the kit exists before submitting the task.
- **Mixing up the task-attachment `role` and the brand-kit-image `role`.** Task `role` is `source` / `reference` / `asset`. Brand-kit image `role` is `logo` / `reference` / `asset`. Similar words, different values.

## Upstream

- [`docs.moda.app/api/brand-kits/listBrandKits`](https://docs.moda.app/api/brand-kits/listBrandKits)
- [`docs.moda.app/api/brand-kits/createBrandKit`](https://docs.moda.app/api/brand-kits/createBrandKit)
- [`docs.moda.app/api/brand-kits/updateBrandKit`](https://docs.moda.app/api/brand-kits/updateBrandKit)
- [`docs.moda.app/api/brand-kits/addBrandKitImage`](https://docs.moda.app/api/brand-kits/addBrandKitImage)
- [`docs.moda.app/api/brand-kits/deleteBrandKit`](https://docs.moda.app/api/brand-kits/deleteBrandKit)
