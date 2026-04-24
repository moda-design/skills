# Authentication (MCP)

The hosted Moda MCP server at `mcp.moda.app/mcp` supports **two** authentication methods. The right choice depends on whether a human is driving the session.

## Which method to use

| Situation | Use |
| --- | --- |
| A person is clicking something and will see the result in chat | **OAuth** |
| A scheduled job runs at 3am | **API key** |
| Different teammates each connect their own editor | **OAuth** (each person signs in as themselves) |
| One service account drives a pipeline | **API key** |
| Need to rotate credentials regularly | **API key** (revoke + regenerate in Settings; no end-user impact) |
| Want the simplest possible setup | **OAuth** (no key management) |

Both methods can be used simultaneously against the same Moda account without conflict.

## OAuth 2.1

**Identity:** per-user. Every tool call runs as the signed-in user. `list_my_canvases` returns their canvases; `start_design_task` bills their team's credits.

**Flow:**

1. Your MCP client sends a request to `mcp.moda.app/mcp`.
2. Server responds `401 Unauthorized`.
3. Your client discovers the OAuth endpoints and opens a browser.
4. User signs into Moda (Clerk-backed).
5. Tokens exchanged; stored by the client.
6. All subsequent calls are authenticated silently.

**Tokens:** access token = 24h JWT (refreshed automatically). Refresh token = 30 days, rotated on each use.

**Hosts that use OAuth:** Claude Desktop, claude.ai (browser), Claude Mobile, Claude Code (default), Cursor, VS Code, Gemini CLI.

## API key

**Identity:** team-level. Every call runs as the key's owner + team.

**Create:** `Settings → Developer → REST API → Create API key`. Copy the `moda_live_…` key immediately — shown once, then hashed at rest. Scope narrowly; store in a secret manager.

**Configure per client:**

```bash
# Claude Code (user-scope to keep the key out of repo configs)
claude mcp add moda https://mcp.moda.app/mcp \
  --transport http \
  --scope user \
  --header "Authorization: Bearer moda_live_…"
```

Cursor / VS Code — add a `headers` field to the server stanza:

```json
{
  "mcpServers": {
    "moda": {
      "type": "streamable-http",
      "url": "https://mcp.moda.app/mcp",
      "headers": {
        "Authorization": "Bearer moda_live_…"
      }
    }
  }
}
```

curl / scripts:

```bash
curl -X POST https://mcp.moda.app/mcp \
  -H "Authorization: Bearer $MODA_API_KEY" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

**Important:** Claude Desktop and claude.ai don't support custom headers in their connector UI — they assume OAuth. Use OAuth for those clients; reserve API keys for Claude Code, Cursor, VS Code, CLI, cron.

## What requires auth

| Action | Auth required |
| --- | --- |
| Fetch a public share link (`moda.app/s/…`) | No |
| Fetch a private canvas (`moda.app/canvas/…`) | Yes |
| List / search your canvases | Yes |
| Create / edit / remix / export | Yes |

Public share links work without auth in both local stdio and remote modes. Everything else needs the remote server + OAuth or API key.

## Revoking access

**OAuth sessions:** remove the connector in the client UI.

- Claude Desktop / claude.ai: **Settings → Connectors** → disconnect or remove.
- Claude Code: `claude mcp remove moda`.
- Cursor: Remove from **Settings → MCP**.
- VS Code: Remove from `settings.json`.

**API keys:** revoke the key itself at **Settings → Developer → REST API**. Every client using that key loses access immediately.

## Common wrong guesses

- **Trying to pass an API key via the Claude Desktop / claude.ai connector UI.** Those clients only support OAuth custom connectors. Use a dedicated coding editor (Claude Code, Cursor, VS Code) for API-key auth.
- **Assuming the local stdio server can access private canvases.** It can't — stdio has no auth. Use the remote server.
- **Putting `moda_live_…` keys in a committed project-scope config**. Use `--scope user` (Claude Code) or a secret manager.
- **Logging tokens**. Only the `moda_live_` prefix is safe to log; the suffix is a secret.

## Upstream

- [`docs.moda.app/mcp/authentication`](https://docs.moda.app/mcp/authentication) — full per-client matrix
- [`docs.moda.app/mcp/setup`](https://docs.moda.app/mcp/setup) — install rituals
