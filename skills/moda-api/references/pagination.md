# Pagination

Every list endpoint on `2026-05-01` uses opaque cursor pagination. No offsets, no `total` count.

## Response shape

```json
{
  "data": [ ... ],
  "next_cursor": "eyJ2IjoxLCJzIjoiMjAyNi0wNC0xNVQxMjow..." | null
}
```

- `data` — the page of items.
- `next_cursor` — opaque signed string. Pass back as `?cursor=<value>` to get the next page. `null` means you've reached the end.

## Iteration pattern

**TypeScript:**

```ts
async function paginate<T>(path: string): Promise<T[]> {
  const all: T[] = [];
  let cursor: string | null = null;
  while (true) {
    const url = new URL(`https://api.moda.app${path}`);
    if (cursor) url.searchParams.set("cursor", cursor);
    url.searchParams.set("limit", "100");
    const { data, next_cursor } = await fetch(url, { headers: HEADERS }).then(r => r.json());
    all.push(...data);
    if (!next_cursor) return all;
    cursor = next_cursor;
  }
}
```

**Python:**

```python
def paginate(path: str) -> list[dict]:
    out = []
    cursor = None
    with httpx.Client(base_url="https://api.moda.app", headers=HEADERS, timeout=30) as c:
        while True:
            params = {"limit": 100}
            if cursor:
                params["cursor"] = cursor
            resp = c.get(path, params=params).json()
            out.extend(resp["data"])
            cursor = resp["next_cursor"]
            if cursor is None:
                return out
```

## Limits

| Parameter | Default | Max |
| --- | --- | --- |
| `limit` | 20 | 100 |

Always request as large a page as you can tolerate — fewer roundtrips, less rate pressure.

## Sort order

List endpoints sort by `(created_at DESC, id DESC)` on immutable columns. This guarantees pagination correctness when rows are added or modified mid-scan — no skips, no duplicates — at the cost of "sort by updated_at" being unavailable.

Client-side sort if you need a different order.

## No `total`

Canonical responses do not include a total count. Computing it on every list call would pressure the DB. If you need an approximate count for a dashboard, cache it separately (e.g. run a count query daily). For a progress bar on a long iteration, the common pattern is "processed 127 so far…" without a denominator.

## Opaque cursors

Cursors are HMAC-signed + base64url-encoded. Don't:

- Parse or mutate the cursor value.
- Attempt to construct one by hand.
- Reuse a cursor from a different list endpoint.

The server detects tampering and returns `400 invalid_request`.

Cursors are valid across sessions but have a bounded TTL — don't store one for a week and expect it to resume correctly. For long-running iterations (> a few hours), consider re-starting from the beginning.

## Endpoints that paginate

All of these return `{data, next_cursor}`:

- `GET /v1/canvases`
- `GET /v1/canvases/search`
- `GET /v1/tasks`
- `GET /v1/brand-kits`
- `GET /v1/organizations`
- `GET /v1/events`

Single-resource endpoints (`GET /v1/canvases/{id}`, `GET /v1/tasks/{id}`, `GET /v1/credits`, etc.) don't paginate.

## Concurrency

Don't parallelize pagination. Each page depends on the previous one's cursor. Parallelize the **work done per item** inside a page instead.

## Migration from offset pagination

If you're carrying code from the legacy `2026-04-12` shape:

```python
# Legacy (2026-04-12):
offset = 0
while True:
    resp = client.get("/canvases", params={"offset": offset, "limit": 50}).json()
    for c in resp["canvases"]:
        yield c
    if not resp["has_more"]:
        break
    offset += 50

# Canonical (2026-05-01):
cursor = None
while True:
    params = {"limit": 50}
    if cursor:
        params["cursor"] = cursor
    resp = client.get("/canvases", params=params).json()
    for c in resp["data"]:
        yield c
    cursor = resp["next_cursor"]
    if cursor is None:
        break
```

## Common wrong guesses

- **Expecting `total` in the response.** Not there. Compute separately if you need it.
- **Parsing / mutating cursors.** Opaque; server rejects tampered values.
- **Passing `offset=` as a fallback.** Ignored (or rejected, depending on endpoint) on `2026-05-01`. Use cursor.
- **Holding a cursor for days.** Cursors expire; restart the iteration.
- **Parallel page fetches.** Each page depends on the prior cursor.
- **Reading `response.canvases` / `response.tasks` / `response.brand_kits`.** Canonical always puts items under `data`.

## Upstream

- [`docs.moda.app/api/versioning`](https://docs.moda.app/api/versioning) — migration map
- Per-endpoint docs at [`docs.moda.app/api/{canvases,tasks,brand-kits,organizations}/*`](https://docs.moda.app/api)
