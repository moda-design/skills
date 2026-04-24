# Errors

Every error response carries a single typed envelope under an `error` key. Branch on `type`, not HTTP status.

## Shape

```json
{
  "error": {
    "type": "not_found",
    "code": "file_not_found",
    "message": "Canvas cvs_abc123 not found",
    "doc_url": "https://docs.moda.app/errors/file_not_found",
    "request_id": "019d8996-16b3-73ee-841a-5bc5038eb972",
    "details": null,
    "retry_after_ms": null,
    "causes": null
  }
}
```

## Fields

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | Stable high-level category. Branch your retry logic on this. |
| `code` | string | Narrow machine-readable identifier. Stable once published. |
| `message` | string | For developers. Not localized, not user-facing. **Don't parse.** |
| `doc_url` | string | Permalink to the doc page for this `code`. |
| `request_id` | string | Correlator. Also echoed in the `X-Request-ID` response header. |
| `details` | object / null | Code-specific. Example for `validation_failed`: `{"fields": [{"field": "body.canvas_id", "code": "string_too_short"}]}` |
| `retry_after_ms` | number / null | Hint for transient / rate-limited errors |
| `causes` | array / null | Nested envelopes for aggregated failures (e.g. multi-page export with per-page errors) |

## Types (branch on these)

| Type | HTTP | Retryable? | Action |
| --- | --- | --- | --- |
| `invalid_request` | 400 | No | Fix the request shape / values |
| `authentication` | 401 | No | Renew / check the API key |
| `permission` | 403 | No | Missing scope, or resource belongs to another team |
| `not_found` | 404 | No | Bad ID, or the key's team doesn't see it |
| `conflict` | 409 | No | Name collision, resource state conflict |
| `idempotency_conflict` | 409 | No | Same `idempotency_key`, different body |
| `unprocessable` | 422 | No | Well-formed request but validation failed |
| `rate_limited` | 429 | Yes | Respect `Retry-After` header (seconds) or `retry_after_ms` |
| `upstream_error` | 502 / 503 / 504 | Yes | Transient — back off and retry |
| `internal_error` | 500 | Yes | Server bug — retry with backoff; include `request_id` when reporting |

## Selected codes worth knowing

| Code | Type | Typical trigger |
| --- | --- | --- |
| `unsupported_version` | `invalid_request` | Unknown `Moda-Version` header. `details.supported` lists valid versions. |
| `validation_failed` | `unprocessable` | Body field failed a validation rule. `details.fields[]` names the offenders. |
| `share_link_revoked` | `not_found` | Share link exists but is disabled. |
| `share_link_not_found` | `not_found` | No share with that token. |
| `scraping_user_error` | `unprocessable` | Brand-kit URL scrape failed (blocked by robots, 404, etc.). |
| `canvas_active_job` | `conflict` | Export attempted on a canvas with an in-flight design task. `409 + Retry-After: 10`. See [`canvases-and-exports.md`](./canvases-and-exports.md). |

## Retry rules

| Error type | Retry rule |
| --- | --- |
| `rate_limited` | Sleep `Retry-After` seconds (or `retry_after_ms`); retry. Exponential backoff on repeats. |
| `upstream_error` | Sleep 1s, 5s, 30s on attempts 1, 2, 3. Give up after 3. |
| `internal_error` | Same as `upstream_error`. |
| Everything else | Don't retry. |

Never silently retry `invalid_request` / `authentication` / `permission` / `not_found` / `conflict` / `idempotency_conflict` / `unprocessable` — they're deterministic.

## Rate limiting

- Surfaced as `429 rate_limited` with `Retry-After` header (seconds).
- Applied per API key and per endpoint (e.g. exports are individually rate-capped).
- Slow down, don't hammer.
- The `RateLimit-*` response headers standardized in RFC 9240 are **not shipped yet**. Don't read them. Use `Retry-After` and the error's `retry_after_ms`.

## Logging & support

- **Always log `request_id`** on every error. When you email support@moda.app, include it.
- Log `type` and `code`; don't log `message` as the signal (it can change without notice).
- Redact the API key from any log line.

## Error handling template (TypeScript)

```ts
async function modaFetch(path: string, init?: RequestInit) {
  const res = await fetch(`https://api.moda.app${path}`, {
    ...init,
    headers: { ...HEADERS, ...(init?.headers ?? {}) },
  });
  if (res.ok) return res.json();

  const body = await res.json().catch(() => null);
  const err = body?.error;
  if (!err) throw new Error(`Moda ${res.status} (no envelope)`);

  if (err.type === "rate_limited" || err.type === "upstream_error" || err.type === "internal_error") {
    const ra = Number(res.headers.get("Retry-After") ?? 0) * 1000 || err.retry_after_ms || 3000;
    await new Promise(r => setTimeout(r, ra));
    return modaFetch(path, init); // caller should cap recursion
  }

  throw new Error(
    `Moda ${err.type}/${err.code}: ${err.message} (request_id=${err.request_id})`,
  );
}
```

## Error handling template (Python)

```python
import time, httpx

def moda_fetch(client: httpx.Client, method: str, path: str, *, attempt: int = 1, **kw):
    r = client.request(method, path, **kw)
    if r.is_success:
        return r.json()

    body = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
    err = body.get("error") or {}

    retryable = {"rate_limited", "upstream_error", "internal_error"}
    if err.get("type") in retryable and attempt <= 3:
        ra = int(r.headers.get("Retry-After", 0)) or ((err.get("retry_after_ms") or 3000) // 1000) or 3
        time.sleep(ra)
        return moda_fetch(client, method, path, attempt=attempt + 1, **kw)

    raise RuntimeError(
        f"Moda {err.get('type')}/{err.get('code')}: {err.get('message')} "
        f"(request_id={err.get('request_id')})"
    )
```

## Common wrong guesses

- **Branching on HTTP status only.** Status codes collapse types (both `rate_limited` and `idempotency_conflict` can be 409-adjacent in practice). Branch on `type`.
- **Parsing `message`.** Can change without notice. Use `type` and `code` for logic; `message` for display only.
- **Retrying `not_found` / `permission`.** Deterministic.
- **Ignoring `Retry-After` on `429`.** You'll be back to rate-limited in seconds.
- **Expecting `RateLimit-Limit` / `RateLimit-Remaining` / `RateLimit-Reset` response headers.** Not shipped yet. Use `Retry-After` and `retry_after_ms`.
- **Not including `request_id` in support requests.** Without it, logs are hard to find.

## Upstream

- [`docs.moda.app/api#error-format`](https://docs.moda.app/api#error-format)
- Per-code docs at `docs.moda.app/errors/<code>` (linked from every envelope's `doc_url`)
