# Moda Skills

> **Create editable, brand-aligned slides and designs.**

Moda is an AI design agent that creates brand-aligned slides, one-pagers, ads, graphics, and more on a fully editable canvas. This repo ships two installable agent skills that teach any AI agent to drive Moda like a power user:

- [`moda-mcp`](./skills/moda-mcp/SKILL.md) — the Moda MCP server. Kick off designs from a conversation in Claude / Cursor / VS Code / Gemini. Generate a deck from a prompt, spin up variations in bulk, customize a template for a prospect, pull an existing canvas into chat to revise, or turn a Moda canvas into production code.
- [`moda-api`](./skills/moda-api/SKILL.md) — the Moda REST API. Scheduled jobs, CI pipelines, webhook receivers, and backend integrations authenticated with an API key.

Install once and your agent knows the canonical design-creation flow, the prompt-gathering ritual before `start_design_task`, the brand-kit default, the 2–10 minute async task lifecycle, the `format_category` disambiguation table (including `carousel`), the prefixed-ID rule, the typed error envelope, and the webhook verification pattern — without re-deriving them from the docs every time.

📖 **Full docs and install walkthroughs:** [docs.moda.app/mcp/agent-skill](https://docs.moda.app/mcp/agent-skill)

## Which install should I pick?

| Situation | Install path |
| --- | --- |
| You're using Codex and want skills + MCP setup in one package | **Codex plugin** — install from the plugin marketplace source below |
| You already have the Moda MCP connected, or only want the REST-API skill | **Vercel `skills` CLI** — `npx skills add moda-design/skills` (skills only, no MCP touch) |
| You're new to Moda and want one-shot skills + MCP setup | **Editor-native plugin** — pick your editor below |
| You're on Claude Desktop, claude.ai, or Claude Mobile | **OAuth Custom Connector** — pair with `npx skills add` on a machine where you code |
| You write raw system prompts or use the Claude Agent SDK | **Manual include** — `@include skills/moda-mcp/SKILL.md` |

Every install path ultimately surfaces the same Markdown files under [`skills/`](./skills/). The per-editor manifests (`.claude-plugin/`, `.cursor-plugin/`, `gemini-extension.json`, `.mcp.json`) just bundle them with the right install ritual for each host.

## Install

### Codex — plugin (bundles skills + MCP)

Add the Moda marketplace source, then install the Moda plugin from Codex's plugin browser:

```bash
codex plugin marketplace add moda-design/skills
codex
/plugins
```

In the plugin browser, choose the **Moda** marketplace, open **Moda**, and select **Install plugin**. Start a new thread after installation.

The plugin registers the Moda MCP server from [`.mcp.json`](./.mcp.json). If Codex does not prompt for OAuth during install or first use, run:

```bash
codex mcp login moda
```

The Codex plugin also bundles both skills in [`skills/`](./skills/), so Codex can load the right Moda workflow before it calls MCP tools. Accounts with the live canvas feature enabled can open the interactive canvas editor inline in Codex.

For local branch testing from a clone of this repo, run:

```bash
codex plugin marketplace add .
```

### Claude Code — plugin (bundles skills + MCP)

```bash
claude /plugin marketplace add moda-design/skills
claude /plugin install moda
```

Claude Code registers both skills and adds the `moda` MCP server from [`.mcp.json`](./.mcp.json). The first time a tool fires, you'll sign in via OAuth in your browser. If you already have a `moda` server configured, disable the plugin's bundled MCP in plugin settings or use the skills-only path instead.

### Claude Code — skills only (no MCP change)

```bash
npx skills add moda-design/skills -a claude-code
```

Installs both skills under `.claude/skills/`. Use this if you already connected the Moda MCP (or prefer to connect it manually — see the [Moda MCP setup docs](https://docs.moda.app/mcp/setup)).

If you only want one skill:

```bash
npx skills add moda-design/skills --skill moda-mcp -a claude-code
npx skills add moda-design/skills --skill moda-api -a claude-code
```

### Cursor — plugin

```
/add-plugin moda-design/skills
```

Cursor reads [`.cursor-plugin/plugin.json`](./.cursor-plugin/plugin.json) and auto-registers the skills plus the MCP server. The OAuth flow runs on first tool call. Skills-only fallback:

```bash
npx skills add moda-design/skills -a cursor
```

Manual MCP setup lives in [`.cursor/mcp.json`](https://docs.moda.app/mcp/setup) — same `streamable-http` config:

```json
{
  "mcpServers": {
    "moda": {
      "type": "streamable-http",
      "url": "https://mcp.moda.app/mcp"
    }
  }
}
```

### Claude Desktop / claude.ai (browser) / Claude Mobile

First add the Moda Custom Connector:

1. Open **Customize** in the sidebar → **+** → **Add custom connector**.
2. **Name**: `Moda`. **URL**: `https://mcp.moda.app/mcp`. Click **Add**, then **Connect** and sign in.

Then add the skill. Two options:

- **Upload the skill zip** (no terminal needed): download [`moda-mcp.zip`](https://github.com/moda-design/skills/releases/latest/download/moda-mcp.zip) from the latest release, then in claude.ai go to **Settings → Capabilities → Skills → Upload skill** and select the file. (Use the per-skill `moda-mcp.zip`, not the bundled `skills.zip` — claude.ai's uploader requires a single skill per zip.)
- **`npx skills add`**: on a machine where you also code, run `npx skills add moda-design/skills`.

Team/Enterprise claude.ai users: an admin must first add the Moda connector in **Admin Settings > Connectors**.

Mobile picks up connectors you've added on claude.ai automatically.

### VS Code

Add to your user or workspace `settings.json`:

```json
{
  "mcp": {
    "servers": {
      "moda": {
        "type": "streamable-http",
        "url": "https://mcp.moda.app/mcp"
      }
    }
  }
}
```

Then install the skills:

```bash
npx skills add moda-design/skills -a vscode
```

### Gemini CLI

```bash
gemini extensions install https://github.com/moda-design/skills
gemini /mcp auth moda
```

The extension manifest at [`gemini-extension.json`](./gemini-extension.json) registers the MCP server; the `auth` step opens the OAuth flow.

### Other agents / raw `CLAUDE.md` include

For the Claude Agent SDK, Continue, Windsurf, or any agent that reads Markdown from a known path, either:

- Run `npx skills add moda-design/skills -a <agent>` (the CLI supports 45+ agents).
- Or include the SKILL.md directly in your system prompt:

  ```markdown
  @include skills/moda-mcp/SKILL.md
  @include skills/moda-api/SKILL.md
  ```

For HTTP clients that don't have a plugin concept, hand-configure from [`.mcp.json`](./.mcp.json) — the URL is `https://mcp.moda.app/mcp`.

## What's in each skill

### [`moda-mcp`](./skills/moda-mcp/SKILL.md)

For agents running inside chat / IDE hosts (Claude Desktop, Claude.ai, Claude Code, Claude Mobile, Cursor, VS Code, Gemini CLI). OAuth-authenticated by default.

Covers the 17 MCP tools, the session-context ritual (`get_context` / `set_context`, 24h TTL), the **required prompt-gathering checklist** before any `start_design_task` call, brand kits (create from a website URL, `skip_brand_kit`), attachments (file-id + role vs URL form), the 2–10 minute async task lifecycle, the seven `format_category` values including `carousel` (Instagram / LinkedIn / story), design-to-code via `get_moda_canvas`, and the known wrong guesses that break tasks.

Bundled recipes: brief-to-deck, customize-for-prospect, bulk-variants, pull-existing-canvas, design-to-code, onboard-new-brand, iterate-in-conversation.

### [`moda-api`](./skills/moda-api/SKILL.md)

For server-side integrations authenticated with a `moda_live_…` API key — scheduled jobs, CI pipelines, webhook receivers, backend workers. No human in the loop.

Covers Bearer auth and the 13 scopes, `Moda-Version: 2026-05-01` pinning, the canonical Task envelope (`{id, kind, status, result, error, progress, links, retry_after_ms}`), prefixed-ID strictness in bodies vs tolerance in path parameters, cursor pagination, the typed error envelope with `request_id`, `idempotency_key` on `POST /v1/tasks`, `Prefer: wait` caps and when it's useful (brand-kit creation, not design tasks), `callback_url` webhook verification, and the synchronous export endpoint with its `409 Conflict + Retry-After: 10` "active task in progress" state.

Bundled recipes: scheduled-generation, bulk-personalization, export-pipeline, webhook-receiver, brief-to-deck-pdf-intake, design-to-code-ci (with TypeScript + Python examples each).

## Principles

- **Second-person, imperative voice.** "Call `set_context` first." Not "you might want to."
- **Skills are summons, not substitutes.** This repo compresses the load-bearing facts; [`docs.moda.app`](https://docs.moda.app) is the source of truth. Every reference links back.
- **Every example is canonical.** `moda_live_…` keys, `Moda-Version: 2026-05-01` on every write, every ID in a JSON body is prefixed (`cvs_…`, `task_…`, `bk_…`, `file_…`).
- **Status vocabulary is surface-specific.** The MCP tools (`get_task_status`) use `queued` / `running` / `completed` / `failed` / `cancelled`. The canonical REST API (`GET /v1/tasks/{id}`) uses `queued` / `running` / `succeeded` / `failed` / `canceled` / `expired`. Each skill uses the vocabulary of its surface — don't mix them up.
- **Every reference file ends with a "Common wrong guesses" section.** Bare UUIDs in bodies, `format_category='pdf'` for an Instagram post, treating a `not_ready` export as an error, polling without `retry_after` — these are the real failure modes agents repeat.

## Troubleshooting

**MCP server not connecting**

- **Claude Desktop**: Check Moda appears under **Settings → Connectors**. Re-add if missing; restart the app.
- **Claude.ai (browser)**: Check [claude.ai/settings](https://claude.ai/settings) → **Connectors**. Remove and re-add.
- **Claude Code**: `claude /mcp` to list servers. `claude mcp remove moda` and re-add.
- **Claude Mobile**: Connectors sync from claude.ai. Add there first, then restart the mobile app.
- **Cursor**: Check **Cursor Settings → MCP**. Try restarting the server from the panel.
- **VS Code**: Confirm the stanza is in user or workspace `settings.json`. Restart VS Code after changes.

Full MCP setup + troubleshooting lives in the canonical docs: [docs.moda.app/mcp/setup](https://docs.moda.app/mcp/setup).

**Skills not showing up**

- Confirm install target: `npx skills add moda-design/skills --list` shows both skills.
- Claude Code reads `~/.claude/skills/` (user) or `./.claude/skills/` (project). Verify the files are there.
- Skills load when the conversation matches their `description` — if yours doesn't match, try prompting explicitly: "use the moda-mcp skill to ..."

**`callback_url` rejected on a design task**

The `callback_url` parameter is **API-key-auth only**. OAuth-authenticated MCP callers get `400` ("callback_url is only supported for API-key authenticated callers"). Use polling from the MCP surface, or issue the task from a server with an API key.

## Canonical Moda docs

- [MCP overview](https://docs.moda.app/mcp) · [Agent skill install guide](https://docs.moda.app/mcp/agent-skill) · [Setup](https://docs.moda.app/mcp/setup) · [Tools reference](https://docs.moda.app/mcp/tools) · [Creating designs](https://docs.moda.app/mcp/create-designs) · [Design-to-code](https://docs.moda.app/mcp/design-to-code) · [MCP authentication](https://docs.moda.app/mcp/authentication)
- [REST API overview](https://docs.moda.app/api) · [Authentication](https://docs.moda.app/api/authentication) · [Versioning](https://docs.moda.app/api/versioning) · [Webhooks](https://docs.moda.app/api/webhooks)
- Plain-text for any LLM: [`llms.txt`](https://docs.moda.app/llms.txt) · [`llms-full.txt`](https://docs.moda.app/llms-full.txt)

## Issues & feedback

File issues at [github.com/moda-design/skills/issues](https://github.com/moda-design/skills/issues). Product feedback on Moda itself goes to [support@moda.app](mailto:support@moda.app).

## License

MIT — see [LICENSE](./LICENSE).
