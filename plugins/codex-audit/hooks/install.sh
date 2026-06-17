#!/usr/bin/env bash
set -euo pipefail

# Codex Audit - install.sh
# Usage: ./install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
mkdir -p "$CODEX_DIR"

# 1. Enable the Codex hooks feature flag (idempotent).
# The canonical key is "hooks"; "codex_hooks" is a deprecated alias.
if [[ -f "$CONFIG_TOML" ]] && grep -qE '^[[:space:]]*(hooks|codex_hooks)[[:space:]]*=[[:space:]]*true' "$CONFIG_TOML"; then
  echo "hooks already enabled in $CONFIG_TOML"
elif [[ -f "$CONFIG_TOML" ]] && grep -qE '^[[:space:]]*\[features\]' "$CONFIG_TOML"; then
  TMP="$(mktemp)"
  awk '1; /^[ \t]*\[features\]/{print "hooks = true"}' "$CONFIG_TOML" > "$TMP"
  mv "$TMP" "$CONFIG_TOML"
  echo "Added hooks = true under [features] in $CONFIG_TOML"
else
  printf '\n[features]\nhooks = true\n' >> "$CONFIG_TOML"
  echo "Enabled [features] hooks = true in $CONFIG_TOML"
fi

# 2. Copy hook scripts into ~/.codex and make them executable.
cp "$SCRIPT_DIR/post_turn.sh" "$CODEX_DIR/post_turn.sh"
cp "$SCRIPT_DIR/tool_audit.sh" "$CODEX_DIR/tool_audit.sh"
chmod +x "$CODEX_DIR/post_turn.sh" "$CODEX_DIR/tool_audit.sh"
echo "Installed post_turn.sh and tool_audit.sh to $CODEX_DIR"

# 3. Replace hooks.json with one pointing at the manually-installed scripts in $HOME/.codex/.
# The plugin's hooks/hooks.json uses $PLUGIN_ROOT which is only set in plugin mode;
# for a manual install we generate a standalone version with absolute paths instead.
HOOKS_DEST="$CODEX_DIR/hooks.json"
sed "s|\$PLUGIN_ROOT/hooks|$CODEX_DIR|g" "$SCRIPT_DIR/hooks.json" > "$HOOKS_DEST"
echo "Installed $HOOKS_DEST"

echo ""
echo "Hooks installed. SessionStart/PreToolUse/PostToolUse/UserPromptSubmit/Stop are active."
echo "Set the following environment variables before starting Codex:"
echo ""
echo "  export AIGW_PROXY_URL=\"<audit-server-url>\""
echo "  export AIGW_PROXY_API_KEY=\"<api-key>\""
echo ""
echo "Restart Codex for the changes to take effect."
