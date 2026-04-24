# Session context

Moda MCP is stateful about which organization and team you're working in. `set_context` / `get_context` / `list_organizations` manage this.

## The rule

Every workspace-scoped tool — `list_brand_kits`, `create_brand_kit`, `update_brand_kit`, `start_design_task`, `remix_design`, `upload_file` — reads from session context by default. You can override per-call with explicit `org_id` / `team_id` without changing the session default.

## TTL

Session context persists **24 hours** across reconnects (tied to the OAuth session / API key owner). Users don't need to re-set it on every new conversation.

## The ritual

On a fresh session where the user belongs to more than one org or team:

```
context = get_context()
# "Organization: Acme Corp | Team: Design Team"
# or "No session context set. Call set_context to choose your organization and team."
```

If no context is set, the server falls back to the user's primary workspace. That's usually fine for a single-org user, but surprising for someone on multiple teams.

To switch workspaces:

```
orgs = list_organizations()
# [{ id, name, role, teams: [{ id, name, is_default }] }]
set_context(org_name="Acme Corp", team_name="Marketing")
# "Context set to organization 'Acme Corp' and team 'Marketing'. All subsequent operations will use this workspace."
```

After `set_context`, every subsequent workspace-scoped tool uses the new workspace automatically. You don't need to pass `org_id` / `team_id` on each call unless you want to override just once.

## Per-call overrides

All workspace-scoped tools accept `org_id` and `team_id` as optional overrides:

```
list_brand_kits(team_id="660e8400-e29b-41d4-a716-446655440000")
# uses this team even if session context says something different; doesn't change session default
```

Use per-call overrides when the user says "show me brand kits for my other team" without implying a permanent switch.

## Naming in conversation

Prefer names over IDs when talking to the user. IDs are included in responses but they're noise in chat. "Switch to Acme Corp / Marketing" beats "set_context with team_id `660e8400-…`."

## Common wrong guesses

- **Forgetting to call `set_context` on a multi-org user** and creating designs in the wrong workspace. Run `get_context` early; if it says "No session context set" and the user has more than one org, ask.
- **Calling `set_context` every turn**. It persists 24 hours; once per session is enough.
- **Passing an org/team ID to `set_context`**. `set_context` takes **names** (`org_name`, `team_name`), not IDs. Case-insensitive.
- **Assuming `org_id` on a per-call override permanently switches the session**. It does not — it's a one-call override.

## Upstream

Full details: [`docs.moda.app/mcp/tools#set_context`](https://docs.moda.app/mcp/tools#set_context) · [`docs.moda.app/mcp/tools#list_organizations`](https://docs.moda.app/mcp/tools#list_organizations).
