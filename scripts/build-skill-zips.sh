#!/usr/bin/env bash
#
# Build distributable zip artifacts for the Moda skills.
#
# Produces, into ./dist:
#   - moda-mcp.zip   — just the moda-mcp skill (one top-level folder)
#   - moda-api.zip   — just the moda-api skill (one top-level folder)
#   - skills.zip     — both skills bundled together
#
# The per-skill zips each contain exactly one top-level folder with
# exactly one SKILL.md inside — the shape claude.ai's skill uploader
# requires. The bundled skills.zip has two top-level folders, so it is
# NOT claude.ai-uploadable; it's kept for tooling that wants everything
# in a single download.
#
# Run from anywhere: `bash scripts/build-skill-zips.sh`
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"

rm -rf "$DIST"
mkdir -p "$DIST"

cd "$ROOT/skills"

# Per-skill artifacts — each is a single top-level folder.
for skill in moda-mcp moda-api; do
  if [ ! -f "$skill/SKILL.md" ]; then
    echo "error: skills/$skill/SKILL.md not found" >&2
    exit 1
  fi
  zip -r -q "$DIST/$skill.zip" "$skill" -x "*.DS_Store"
  echo "built dist/$skill.zip"
done

# Full bundle — both skills. Two top-level folders, so not
# claude.ai-uploadable; for tooling that wants everything at once.
zip -r -q "$DIST/skills.zip" moda-mcp moda-api -x "*.DS_Store"
echo "built dist/skills.zip"
