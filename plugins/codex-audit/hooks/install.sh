#!/usr/bin/env bash
set -euo pipefail

# Codex Audit - install.sh
# Usage: ./install.sh --server <url> --key <api-key> --developer <username>

SERVER=""
API_KEY=""
DEVELOPER=""

usage() {
  echo "Usage: $0 --server <url> --key <api-key> --developer <username>"
  echo ""
  echo "  --server     Base URL of your audit server (e.g. https://audit.example.com)"
  echo "  --key        API key sent as X-Api-Key header"
  echo "  --developer  Developer identifier included in every payload (default: \$(whoami))"
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)    SERVER="$2";    shift 2 ;;
    --key)       API_KEY="$2";   shift 2 ;;
    --developer) DEVELOPER="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

# Validate required args
if [[ -z "$SERVER" ]]; then
  echo "Error: --server is required"
  usage
fi
if [[ -z "$API_KEY" ]]; then
  echo "Error: --key is required"
  usage
fi
if [[ -z "$DEVELOPER" ]]; then
  DEVELOPER="$(whoami)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
mkdir -p "$CODEX_DIR"

# 1. Enable the experimental Codex hooks feature flag (idempotent).
if [[ -f "$CONFIG_TOML" ]] && grep -qE '^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true' "$CONFIG_TOML"; then
  echo "codex_hooks already enabled in $CONFIG_TOML"
elif [[ -f "$CONFIG_TOML" ]] && grep -qE '^[[:space:]]*\[features\]' "$CONFIG_TOML"; then
  # Note: [ \t] (not [[:space:]]) so the match works under mawk as well as gawk.
  TMP="$(mktemp)"
  awk '1; /^[ \t]*\[features\]/{print "codex_hooks = true"}' "$CONFIG_TOML" > "$TMP"
  mv "$TMP" "$CONFIG_TOML"
  echo "Added codex_hooks = true under [features] in $CONFIG_TOML"
else
  printf '\n[features]\ncodex_hooks = true\n' >> "$CONFIG_TOML"
  echo "Enabled [features] codex_hooks = true in $CONFIG_TOML"
fi

# 2. Copy hook scripts into ~/.codex and make them executable.
cp "$SCRIPT_DIR/post_turn.sh" "$CODEX_DIR/post_turn.sh"
cp "$SCRIPT_DIR/tool_audit.sh" "$CODEX_DIR/tool_audit.sh"
chmod +x "$CODEX_DIR/post_turn.sh" "$CODEX_DIR/tool_audit.sh"
echo "Installed post_turn.sh and tool_audit.sh to $CODEX_DIR"

# 3. Install hooks.json without clobbering an existing one.
HOOKS_DEST="$CODEX_DIR/hooks.json"
if [[ -f "$HOOKS_DEST" ]]; then
  echo ""
  echo "WARNING: $HOOKS_DEST already exists — not overwriting."
  echo "Merge the PreToolUse / PostToolUse / Stop blocks from:"
  echo "  $SCRIPT_DIR/hooks.json"
else
  cp "$SCRIPT_DIR/hooks.json" "$HOOKS_DEST"
  echo "Installed $HOOKS_DEST"
fi

if [[ -f "$HOME/.zshrc" ]]; then
  SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
  SHELL_RC="$HOME/.bashrc"
else
  echo "Could not find ~/.zshrc or ~/.bashrc."
  echo "Please add the following to your shell config manually:"
  echo ""
  echo "  export AIGW_PROXY_URL=\"$SERVER\""
  echo "  export AIGW_PROXY_API_KEY=\"$API_KEY\""
  echo "  export CLAUDE_AUDIT_DEVELOPER_ID=\"$DEVELOPER\""
  exit 1
fi

# Remove any existing Codex Audit block
if grep -q "# Codex Audit" "$SHELL_RC"; then
  # Use a temp file to rewrite without the block
  TMP="$(mktemp)"
  awk '/# Codex Audit \(added by install\.sh\)/{found=1} found && /^$/{found=0; next} !found' "$SHELL_RC" > "$TMP"
  mv "$TMP" "$SHELL_RC"
fi

# Append new block
cat >> "$SHELL_RC" <<EOF

# Codex Audit (added by install.sh)
export AIGW_PROXY_URL="$SERVER"
export AIGW_PROXY_API_KEY="$API_KEY"
export CLAUDE_AUDIT_DEVELOPER_ID="$DEVELOPER"
EOF

echo "Credentials written to $SHELL_RC"
echo ""
echo "Run the following to apply immediately:"
echo "  source $SHELL_RC"
echo ""
echo ""
echo "Hooks installed. PreToolUse/PostToolUse capture Bash tool calls; Stop captures turns."
echo "Restart Codex for the changes to take effect."
