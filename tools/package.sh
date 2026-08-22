#!/usr/bin/env bash
#
# package.sh - build dist/grokify.plugin.
#
# One artifact, because there is only one thing to install. The repository is
# the plugin: .claude-plugin/plugin.json, .mcp.json, the host bridge under
# servers/, and the skill under skills/. Zipping it from its own root, with no
# enclosing folder, is the layout the plugin installer reads.
#
# A skill-only archive used to be built here too. It was removed on purpose. A
# skill archive cannot carry an MCP server, so uploading one to the desktop app
# installs something that loads and then cannot reach Grok at all - the exact
# failure this project exists to fix.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
SKILL_DIR="$ROOT/skills/grokify"

command -v zip >/dev/null 2>&1 || { echo "package: the 'zip' command is required" >&2; exit 1; }

for f in "$ROOT/.claude-plugin/plugin.json" "$ROOT/.mcp.json" \
         "$ROOT/servers/grokify-host.mjs" "$SKILL_DIR/SKILL.md"; do
  [ -f "$f" ] || { echo "package: missing $f" >&2; exit 1; }
done

# Keeping the skill's frontmatter inside the six fields the Agent Skills spec
# allows is not required by the plugin installer. It is kept so the skill folder
# stays valid on its own, for anyone who copies it into ~/.claude/skills.
ALLOWED="name description license compatibility metadata allowed-tools"
awk '/^---$/{n++; next} n==1 && /^[a-zA-Z][a-zA-Z0-9_-]*:/ {sub(/:.*/, ""); print}' "$SKILL_DIR/SKILL.md" \
| while read -r key; do
    case " $ALLOWED " in
      *" $key "*) ;;
      *) echo "package: frontmatter key '$key' is not in the Agent Skills spec ($ALLOWED)" >&2; exit 1 ;;
    esac
  done

# Both manifests are read by the installer before anything runs, so a syntax
# error here is an install that fails with nothing useful to say.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$ROOT" <<'PYEOF' || exit 1
import json, os, sys
root = sys.argv[1]
manifest = json.load(open(os.path.join(root, '.claude-plugin', 'plugin.json')))
if 'name' not in manifest:
    sys.exit("package: plugin.json needs a name")

market_path = os.path.join(root, '.claude-plugin', 'marketplace.json')
if os.path.exists(market_path):
    market = json.load(open(market_path))
    names = [p.get('name') for p in market.get('plugins', [])]
    if manifest['name'] not in names:
        sys.exit("package: marketplace.json does not list %s" % manifest['name'])

mcp = json.load(open(os.path.join(root, '.mcp.json')))
servers = mcp.get('mcpServers', {})
if not servers:
    sys.exit("package: .mcp.json declares no servers")
for name, cfg in servers.items():
    for arg in cfg.get('args', []):
        # A hardcoded path works on the machine that built the archive and
        # nowhere else. ${CLAUDE_PLUGIN_ROOT} is what makes it portable.
        if arg.endswith('.mjs') and '${CLAUDE_PLUGIN_ROOT}' not in arg:
            sys.exit("package: %s points at %s without ${CLAUDE_PLUGIN_ROOT}" % (name, arg))
        rel = arg.replace('${CLAUDE_PLUGIN_ROOT}/', '')
        if arg.endswith('.mjs') and not os.path.exists(os.path.join(root, rel)):
            sys.exit("package: %s points at %s, which is not in the archive" % (name, rel))
PYEOF
fi

if command -v node >/dev/null 2>&1; then
  node --check "$ROOT/servers/grokify-host.mjs" \
    || { echo "package: the host server does not parse" >&2; exit 1; }
fi

rm -rf "$DIST"
mkdir -p "$DIST"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/.claude-plugin"
cp "$ROOT/.claude-plugin/plugin.json" "$STAGE/.claude-plugin/plugin.json"
cp "$ROOT/.mcp.json" "$STAGE/.mcp.json"
cp -R "$ROOT/servers" "$STAGE/servers"
mkdir -p "$STAGE/skills"
cp -R "$SKILL_DIR" "$STAGE/skills/grokify"
cp "$ROOT/README.md" "$STAGE/README.md"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
find "$STAGE" -name '.DS_Store' -delete
chmod +x "$STAGE/skills/grokify/scripts/grokify.sh"

# marketplace.json is deliberately not copied: it describes where to find this
# plugin, which is of no use once you are holding it.
( cd "$STAGE" && zip -r -q "$DIST/grokify.plugin" . )

printf 'built %s (%s bytes)\n' "$DIST/grokify.plugin" \
  "$(wc -c < "$DIST/grokify.plugin" | tr -d ' ')"
