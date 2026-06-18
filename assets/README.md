# Codex Plugin Assets

The Codex plugin manifest is valid without image assets. Before submitting for marketplace review, add final branded assets here and wire them into `.codex-plugin/plugin.json`.

Recommended files:

- `icon.png` - square composer icon, visible at small sizes.
- `logo.png` - Moda logo for plugin detail pages.
- `live-canvas.png` - screenshot of the live canvas editor rendered inside Codex.
- `design-task.png` - screenshot of a completed design task or export flow.

After assets are added, update the manifest `interface` object with:

```json
{
  "composerIcon": "./assets/icon.png",
  "logo": "./assets/logo.png",
  "screenshots": ["./assets/live-canvas.png", "./assets/design-task.png"]
}
```
