# Design-to-code in CI

**Problem:** You have a canonical Moda canvas that represents your design tokens (colors, fonts, radii, spacing variables). On every push to `main`, regenerate `tailwind.theme.ts` (or equivalent) from the canvas and commit the diff, so code always tracks design.

## Primitives

- `GET /v1/canvases/{id}/tokens` — structured JSON of colors / fonts / radii / variables
- A tiny codegen step in your CI (Node / Python / Deno)
- Commit + PR if the diff is non-empty

Scope: `designs:read` only. No `tasks:write`, no `designs:export`. Create a minimal API key for CI.

## TypeScript — GitHub Actions

`.github/workflows/sync-theme.yml`:

```yaml
name: Sync design tokens
on:
  push:
    branches: [main]
  schedule:
    - cron: "0 9 * * 1"        # also weekly on Monday 09:00 UTC

permissions:
  contents: write
  pull-requests: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }

      - name: Regenerate theme
        env:
          MODA_API_KEY: ${{ secrets.MODA_API_KEY_READONLY }}
          CANVAS_ID:    cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV
        run: node scripts/sync-theme.mjs

      - name: Open PR if changed
        uses: peter-evans/create-pull-request@v6
        with:
          branch: design-tokens-sync
          title: "chore: sync design tokens from Moda"
          commit-message: "chore: sync design tokens from Moda"
          body: "Auto-generated from [canvas](https://moda.app/canvas/${{ env.CANVAS_ID }})."
```

`scripts/sync-theme.mjs`:

```js
import fs from "node:fs";

const API = "https://api.moda.app/v1";
const HEADERS = {
  Authorization: `Bearer ${process.env.MODA_API_KEY}`,
  "Moda-Version": "2026-05-01",
};

const res = await fetch(`${API}/canvases/${process.env.CANVAS_ID}/tokens`, {
  headers: HEADERS,
});
if (!res.ok) {
  const err = await res.json().catch(() => null);
  console.error("Moda fetch failed:", err?.error ?? res.statusText);
  process.exit(1);
}
const { variables, colors, fonts, radii } = await res.json();

// Emit a predictable, diffable TS file.
const body = `// AUTO-GENERATED — edit the Moda canvas instead.
// Source: cvs_${process.env.CANVAS_ID}
// Generated: ${new Date().toISOString()}

export const theme = {
  colors: {
${Object.entries(variables)
  .filter(([, v]) => typeof v === "string" && v.startsWith("#"))
  .map(([k, v]) => `    ${JSON.stringify(k)}: ${JSON.stringify(v)},`)
  .join("\n")}
  },
  palette: ${JSON.stringify(colors, null, 2).replace(/\n/g, "\n  ")},
  fonts: ${JSON.stringify(fonts, null, 2).replace(/\n/g, "\n  ")},
  radii: ${JSON.stringify(radii, null, 2).replace(/\n/g, "\n  ")},
} as const;
`;

fs.writeFileSync("src/design/theme.ts", body);
console.log("Wrote src/design/theme.ts");
```

## Python — GitLab CI variant

`.gitlab-ci.yml`:

```yaml
sync-theme:
  image: python:3.12
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_COMMIT_REF_NAME == "main"
  before_script:
    - pip install httpx
  script:
    - python scripts/sync_theme.py
    - |
      if ! git diff --quiet src/design/theme.py; then
        git config user.email "ci@example.com"
        git config user.name "CI"
        git checkout -b design-tokens-sync
        git add src/design/theme.py
        git commit -m "chore: sync design tokens from Moda"
        git push origin design-tokens-sync -o merge_request.create
      fi
  variables:
    MODA_API_KEY: $MODA_API_KEY_READONLY
    CANVAS_ID: cvs_01HT9WK8N3M2J4A5Z6P7Q8R9TV
```

`scripts/sync_theme.py`:

```python
import os, sys, datetime, httpx

HEADERS = {
    "Authorization": f"Bearer {os.environ['MODA_API_KEY']}",
    "Moda-Version": "2026-05-01",
}

r = httpx.get(
    f"https://api.moda.app/v1/canvases/{os.environ['CANVAS_ID']}/tokens",
    headers=HEADERS,
    timeout=30,
)
if r.status_code != 200:
    print("Moda fetch failed:", r.json().get("error"))
    sys.exit(1)

tokens = r.json()
generated_at = datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"

with open("src/design/theme.py", "w") as f:
    f.write(f'''"""AUTO-GENERATED — edit the Moda canvas instead.
Source: {os.environ["CANVAS_ID"]}
Generated: {generated_at}
"""

COLORS = {tokens["variables"]!r}
PALETTE = {tokens["colors"]!r}
FONTS = {tokens["fonts"]!r}
RADII = {tokens["radii"]!r}
''')

print("Wrote src/design/theme.py")
```

## Why tokens, not `get_canvas`

`GET /v1/canvases/{id}/tokens` is a dedicated endpoint that returns structured JSON. Parsing tokens out of the pseudo-HTML from `GET /v1/canvases/{id}` works but is fragile — layer names / HTML shape can change without signaling a token change. Use the dedicated endpoint for CI.

## Making it diffable

- **Sort all arrays** before emitting — otherwise insertion order in the canvas creates spurious diffs on every run.
- **Emit a deterministic timestamp header** (or omit the timestamp entirely; git tells you when the file changed).
- **Name variables** in the Moda canvas — named variables land as keys in the `variables` object and become your `colors.primary`, `colors.background`, etc.

## Gotchas

- **Scope the API key narrowly.** `designs:read` only. A leaked CI key with `tasks:write` / `designs:export` is a bigger blast radius.
- **Unknown response fields** may appear over time. Don't fail the build if the JSON has new keys — only fail if the keys you need are missing.
- **Cache-bust properly.** If your codegen reads other files (a base theme, palette overrides), include them in the cache key for the CI action.
- **Don't bypass PR review** by committing directly to `main`. PR the change — design tokens can have visual fallout.
- **The canvas must be team-accessible** to the API key's team. Share links do NOT grant design token reads in CI — use a canvas URL + a team-scoped key.

## See also

- [`../references/canvases-and-exports.md`](../references/canvases-and-exports.md) — tokens endpoint reference
- [`../references/authentication.md`](../references/authentication.md) — scopes
- `moda-mcp/references/design-to-code.md` — the IDE-side story for turning a canvas into code
