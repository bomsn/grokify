#!/usr/bin/env bash
#
# package.sh - build the distributable archives.
#
#   dist/grokify.zip     upload to claude.ai or the Claude desktop app
#   dist/grokify.skill   the same archive, named for hosts that expect it
#
# Both hold a single top-level folder, grokify/, with SKILL.md at the top of
# it. That is the layout the Skills API and the claude.ai uploader accept.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT/skills/grokify"
DIST="$ROOT/dist"

[ -f "$SKILL_DIR/SKILL.md" ] || { echo "package: SKILL.md not found at $SKILL_DIR" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "package: the 'zip' command is required" >&2; exit 1; }

# The upload path accepts only the six Agent Skills frontmatter fields. A field
# outside that set fails the upload with a hard error rather than being ignored,
# so it is worth catching here instead of after the upload.
ALLOWED="name description license compatibility metadata allowed-tools"
awk '/^---$/{n++; next} n==1 && /^[a-zA-Z][a-zA-Z0-9_-]*:/ {sub(/:.*/, ""); print}' "$SKILL_DIR/SKILL.md" \
| while read -r key; do
    case " $ALLOWED " in
      *" $key "*) ;;
      *) echo "package: frontmatter key '$key' is not in the Agent Skills spec ($ALLOWED)" >&2; exit 1 ;;
    esac
  done

rm -rf "$DIST"
mkdir -p "$DIST"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$SKILL_DIR" "$STAGE/grokify"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE/grokify/scripts/grokify.sh"

( cd "$STAGE" && zip -r -q "$DIST/grokify.zip" grokify )
cp "$DIST/grokify.zip" "$DIST/grokify.skill"

printf 'built %s (%s bytes)\n' "$DIST/grokify.zip" "$(wc -c < "$DIST/grokify.zip" | tr -d ' ')"
printf 'built %s\n' "$DIST/grokify.skill"
