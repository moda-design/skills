# Resource IDs

Every Moda resource has a **prefixed wire ID** like `cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV`. The prefix disambiguates the resource type on sight and prevents cross-resource lookup mistakes.

## Prefixes

| Prefix | Resource |
| --- | --- |
| `cvs_` | Canvas |
| `task_` | Task (design / export / remix / brand_kit_extract) |
| `bk_` | Brand kit |
| `file_` | Uploaded file |
| `upl_` | Legacy upload record (use `file_` going forward) |
| `conv_` | Conversation (multi-turn design context) |
| `evt_` | Webhook event |
| `org_` | Organization |
| `team_` | Team |

Encoding: Crockford base32 (no I, L, O, U to avoid visual confusion). Case-insensitive.

## The two strictness rules

### Body fields — strict (prefixed only)

```bash
# GOOD
curl -X POST https://api.moda.app/v1/remix \
  -H "Authorization: Bearer moda_live_..." \
  -H "Moda-Version: 2026-05-01" \
  -H "Content-Type: application/json" \
  -d '{"canvas_id": "cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV"}'

# BAD — 400 invalid_request
curl -X POST https://api.moda.app/v1/remix \
  -H "..." \
  -d '{"canvas_id": "550e8400-e29b-41d4-a716-446655440000"}'
```

Bare UUIDs in body fields get rejected. Responses always come back prefixed, so if you store the ID from a response and pass it in later, you're fine.

### Path parameters — tolerant (either form)

```bash
# BOTH WORK
curl -X POST https://api.moda.app/v1/canvases/cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV/export ...
curl -X POST https://api.moda.app/v1/canvases/550e8400-e29b-41d4-a716-446655440000/export ...
```

Path-parameter tolerance is a convenience for integrators who already hold raw UUIDs from an older system. Always prefer prefixed form in new code.

## Why this design

- Prefixed IDs are self-describing. Pasting one in a log or a PR makes it immediately clear what kind of object it is.
- Strictness in bodies prevents accidental cross-resource confusion (passing a `canvas_id` where a `brand_kit_id` was expected — the server catches it at validation).
- Tolerance in paths avoids breaking older callers who already hold bare UUIDs.

## In responses

Every `id` field in response bodies is prefixed:

```json
{
  "id": "task_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
  "kind": "design",
  "result": {
    "canvas_id": "cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
    "canvas_url": "https://moda.app/canvas/..."
  }
}
```

Store the prefixed form for future calls.

## Webhook payloads

Webhook events carry a prefixed `evt_…` id:

```json
{
  "id": "evt_01HT9WK8N3M2J4A5Z6P7Q8R9TV",
  "type": "task.succeeded",
  "created": "2026-04-15T12:01:00+00:00",
  "api_version": "2026-05-01",
  "data": { "id": "task_01HT9WK8N3M2J4A5Z6P7Q8R9TV", ... }
}
```

Use `id` (the event ID) as an idempotency key in your webhook handler — it's stable across retries.

## Common wrong guesses

- **Sending a bare UUID in a JSON body.** `400 invalid_request`. Always use prefixed IDs in bodies.
- **Storing bare UUIDs from older responses.** They work in path params today, but storing the prefixed form (from any current response) is safer for future use.
- **Parsing the prefix at the client** to dispatch on resource type. Don't — use the `kind` field on task envelopes or the response shape. Prefixes are for humans.
- **Assuming `upl_` and `file_` are interchangeable.** `upl_` is legacy; current uploads return `file_`. Don't mix.

## Upstream

[`docs.moda.app/api/authentication#resource-id-formats`](https://docs.moda.app/api/authentication#resource-id-formats)
