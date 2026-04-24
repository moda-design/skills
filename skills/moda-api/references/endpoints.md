# Endpoints

Compressed catalog of every `2026-05-01` endpoint by router, with scope and a one-line purpose. Not a substitute for the OpenAPI spec — a scannable index.

Base URL: `https://api.moda.app/v1`

## Tasks

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/tasks` | `startTask` | `tasks:write` | Start an AI design task. Returns Task envelope immediately; poll or webhook. |
| GET | `/tasks/{id}` | `getTask` | `tasks:read` | Fetch current task envelope. |
| GET | `/tasks` | `listTasks` | `tasks:read` | Cursor-paginated list of team's tasks. |
| POST | `/tasks/{id}/cancel` | `cancelTask` | `tasks:cancel` | Request cancellation. Returns 202 + updated envelope. |

`Prefer: wait=<s>` accepted on `POST /tasks` and `POST /tasks/{id}/cancel`. Max 30s. See [`task-envelope.md`](./task-envelope.md).

## Remix

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/remix` | `remixCanvas` | `tasks:write` | Duplicate canvas and optionally run a design task on the copy. Always returns a Task envelope (`kind: "remix"`). |

Without a `prompt`: completes synchronously, returns `status: "succeeded"` inline. With a prompt: queues a task, returns non-terminal envelope; poll.

## Canvases

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/canvases` | `listCanvases` | `canvases:read` | Cursor-paginated list of team canvases. |
| GET | `/canvases/search` | `searchCanvases` | `canvases:read` | Full-text search by name/content. |
| GET | `/canvases/{id}` | `getCanvas` | `designs:read` | Fetch canvas spec (pseudo-HTML + CSS). `share_token` query param for public reads. |
| GET | `/canvases/{id}/tokens` | `getCanvasTokens` | `designs:read` | Extract design variables / colors / fonts / radii only. |
| GET | `/canvases/{id}/pages` | `listCanvasPages` | `designs:read` | List page metadata (name, dimensions, node_count). |
| POST | `/canvases/{id}/export` | `exportCanvas` | `designs:export` | **Synchronous** export to PNG / JPEG / PDF / PPTX. Returns `{url, format}`. `409 + Retry-After: 10` when an active design task runs on this canvas. |
| POST | `/canvases/{id}/share` | `makeCanvasPublic` | `canvases:write` | Create / retrieve a public share link. Blocks on thumbnail generation by default; pass `wait_for_thumbnail=false` to skip. |

See [`canvases-and-exports.md`](./canvases-and-exports.md) for the export semantics and the share-token read pattern.

## Brand kits

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/brand-kits` | `listBrandKits` | `brand_kits:read` | Cursor-paginated list. Team is implicit from the API key context. |
| POST | `/brand-kits` | `createBrandKit` | `brand_kits:write` | Extract brand data from a URL (Firecrawl-backed). Returns the kit record. |
| PATCH | `/brand-kits/{id}` | `updateBrandKit` | `brand_kits:write` | Partial update. Array fields (`colors`, `fonts`) replace wholesale. |
| DELETE | `/brand-kits/{id}` | `deleteBrandKit` | `brand_kits:write` | Soft delete. Returns 204. |
| POST | `/brand-kits/{id}/images` | `addBrandKitImage` | `brand_kits:write` | Attach an uploaded file (logo / reference / asset). Requires `file_id` from `POST /uploads`. |

See [`brand-kits.md`](./brand-kits.md) for update semantics.

## Uploads

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/uploads` | `uploadFile` | `uploads:write` | Multipart upload. Returns `{id: "file_...", url, filename, mime_type, size_bytes, was_duplicate}`. |
| POST | `/uploads/from-url` | `uploadFromUrl` | `uploads:write` | Server fetches from a public URL, validates MIME, stores. SSRF-validated. |

Deduplicates by content hash. See [`uploads.md`](./uploads.md).

## Organizations

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/organizations` | `listOrganizations` | `organizations:read` | Cursor-paginated list of orgs + teams the key's owner belongs to. |

Role scoped: admins see all, members see their own.

## Credits

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/credits` | `getCredits` | `credits:read` | Current balance, plan, reset date. `null` fields when billing is disabled. |

## Share links

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| POST | `/share_links/resolve` | `resolveShareLink` | (none — public-ish) | Parse a `moda.app/s/…` URL into `{canvas_id, share_token, permission, expires_at}`. Distinguishes `share_link_revoked` from `share_link_not_found`. |

## Usage / events (observability)

| Verb | Path | Operation | Scope | Purpose |
| --- | --- | --- | --- | --- |
| GET | `/usage` | `getApiUsage` | (admin) | Summary + daily / per-key / per-operation aggregates. 7-day default, 90-day max window. |
| GET | `/events` | `listApiEvents` | (admin) | Cursor-paginated activity log. Rows include HTTP status, `operation_id`, `timestamp`, `trigger_source` (api / mcp). |

Admins see everything; members see only their own keys' events.

## Cross-cutting request headers

| Header | Required | Notes |
| --- | --- | --- |
| `Authorization: Bearer moda_live_…` | Yes (except `/share_links/resolve`) | See [`authentication.md`](./authentication.md) |
| `Moda-Version: 2026-05-01` | Should | Pin in production. Omitting resolves to default. |
| `Content-Type: application/json` | POST / PATCH | |
| `Prefer: wait=<seconds>` | No | On task-shaped POSTs. Max 30s. |
| `Idempotency-Key` (header) | No — **not yet implemented** | Body field `idempotency_key` instead. |

## Cross-cutting response headers

| Header | Always present |
| --- | --- |
| `Moda-Version` | Yes — the resolved version |
| `X-Request-ID` | Yes — matches the `request_id` in error envelopes |
| `Retry-After` | On `429 rate_limited` and `409 canvas_active_job` |

## Common wrong guesses

- **Using the operation ID (`startTask`) as the path.** Operation IDs are for SDKs; the HTTP path is what matters.
- **Expecting `/tasks/{id}/cancel` to be a DELETE.** It's a POST.
- **Confusing `POST /canvases/{id}/share` with generating a share link on every call.** It creates one if missing, returns the existing one otherwise. It also blocks on thumbnail generation by default.
- **Calling `GET /canvases/{id}` without `share_token=` on a share-only-visible canvas.** You'll get `404` — the call resolves through the key's team access, not the share link.
- **Treating `POST /canvases/{id}/export` as async.** It's synchronous. No Task envelope. `409 + Retry-After: 10` is the retry signal when a design task is running on the canvas.

## Upstream

- Full OpenAPI spec: [`docs.moda.app/openapi/moda-public-api.yaml`](https://docs.moda.app/openapi/moda-public-api.yaml)
- Per-endpoint docs: [`docs.moda.app/api/*`](https://docs.moda.app/api)
