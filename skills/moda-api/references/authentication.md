# Authentication (REST API)

## Header

```
Authorization: Bearer moda_live_<suffix>
```

Every request. Always pair with `Moda-Version: 2026-05-01`.

## Creating a key

1. Open the Moda app → **Settings → Developer → REST API → Create Key**.
2. Name the key for the integration it belongs to ("CI Pipeline", "Slack bot").
3. Select the **minimum** scopes the integration needs (table below).
4. Copy the key immediately — it's shown once.
5. Copy the **webhook signing secret** shown in the same banner. This is used to verify webhook payloads. You cannot retrieve it later.

Keys start with `moda_live_`. They are hashed at rest; only the prefix is safe to log. Lost a key? Revoke it and create a new one.

## Scopes (13)

| Scope | Grants |
| --- | --- |
| `canvases:read` | List and search canvases |
| `canvases:write` | Make canvases public (share links); other write ops through tasks/remix |
| `designs:read` | Fetch canvas pseudo-HTML, tokens, page metadata |
| `designs:export` | Export PNG / JPEG / PDF / PPTX |
| `tasks:read` | Get task status; list tasks |
| `tasks:write` | Start design + remix tasks |
| `tasks:cancel` | Cancel in-flight tasks |
| `brand_kits:read` | List brand kits |
| `brand_kits:write` | Create, update, delete brand kits; attach images |
| `uploads:write` | Upload files (multipart + from-URL) |
| `organizations:read` | List organizations and teams |
| `credits:read` | Check credit balance |
| `webhooks:manage` | Webhook configuration (future) |

## Scope recipes by integration type

| Integration | Scopes |
| --- | --- |
| Read-only dashboard (list canvases, show tokens) | `canvases:read`, `designs:read`, `organizations:read` |
| Scheduled design generator with Slack webhook | `brand_kits:read`, `uploads:write`, `tasks:write`, `tasks:read`, `designs:export`, `canvases:read` |
| Export pipeline (every canvas → S3) | `canvases:read`, `designs:export` |
| Theme regeneration in CI | `designs:read` |
| Full-service automation | all scopes (least recommended — split by integration) |

## Security best practices

- **Keep keys server-side.** Never expose them in frontend code, mobile apps, or client bundles.
- **One key per integration.** Revocation affects one system; rotation doesn't cascade.
- **Narrow scopes.** A read-only dashboard shouldn't have `tasks:write`.
- **Rotate on a schedule** or after any suspected leak. Revoke in the app; issue a fresh key; update config.
- **Store in a secret manager.** `.env` works for local dev; production should use Vault / AWS Secrets Manager / GCP Secret Manager / Doppler.
- **Log the `request_id`** from error envelopes — it's how support finds your request in logs. Don't log the key itself.

## Revoking

**Settings → Developer → REST API → Delete.** Takes effect immediately. All requests using that key return `401 Unauthorized` instantly.

## Errors

| Status | Meaning |
| --- | --- |
| `401 authentication` | Missing, invalid, revoked, or expired key |
| `403 permission` | Valid key, but missing the scope for this endpoint, or resource belongs to a different team |

Both come with a `WWW-Authenticate: Bearer` header. Errors carry the standard typed envelope; see [`errors.md`](./errors.md).

## Common wrong guesses

- **Committing a `moda_live_…` key to a repo.** Even private repos leak eventually. Use env vars + a secret manager.
- **Over-scoping.** `webhooks:manage` on a key that only exports is over-privileged. Narrow.
- **Logging the full key for debugging.** Only log the prefix (`moda_live_`) — the suffix is a secret.
- **Using the same key across production and staging.** Keys should be environment-specific so you can revoke independently.
- **Forgetting the webhook signing secret.** It's shown once alongside the key. Store it adjacent to the key in your secret manager — you'll need it to verify webhook payloads.

## Upstream

- [`docs.moda.app/api/authentication`](https://docs.moda.app/api/authentication)
- [`docs.moda.app/api/webhooks`](https://docs.moda.app/api/webhooks) — signing secret details
