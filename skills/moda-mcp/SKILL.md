---
name: moda-mcp
description: READ THIS BEFORE calling any Moda MCP tool. Recommended whenever the Moda MCP server is connected or the user mentions Moda, moda.app, a moda.app/s/ share link, or wants to create, edit, remix, or export a canvas (slide deck, social post, Instagram or LinkedIn carousel, PDF report, diagram, UI mockup), or turn a Moda canvas into code.
---

# moda-mcp

Moda is an AI design agent that creates brand-aligned slides, social posts, one-pagers, ads, and other graphics on a fully editable canvas — and can turn any canvas into production code. The MCP server lets you create designs from a prompt, remix existing canvases, and export to PNG / JPEG / PDF / PPTX.

**Before calling any other Moda MCP tool, call `whoami` first.** Its response points you at `skill://moda-mcp/SKILL.md` — read that resource next, via your client's native resource reader, or the `read_moda_resource` tool if your client can't read resources. That server-side copy is the authoritative, always-current version of this skill: the design-task recipes (create-new-design, edit-existing-canvas, fill-template, rebrand-template, bulk-variants) and the gotchas that silently go wrong (format defaults, task-lifecycle timing, brand-kit resolution, concurrency caps, and more).

This file is intentionally just the bootstrap — the real content lives on the MCP server so it can never drift out of sync with the tools it documents.

## Setup & auth

Per-editor install: [`docs.moda.app/mcp/setup`](https://docs.moda.app/mcp/setup). OAuth vs API-key tradeoffs: [`docs.moda.app/mcp/authentication`](https://docs.moda.app/mcp/authentication). In Claude Desktop / claude.ai, the user must enable the **Moda** connector for the current chat (click **+** → **Connectors**) before any tool call works.
