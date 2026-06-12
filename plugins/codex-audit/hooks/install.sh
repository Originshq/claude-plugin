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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)    SERVER="$2";    shift 2 ;;
    --key)       API_KEY="$2";   shift 2 ;;
    --developer) DEVELOPER="$2"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

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

if grep -q "# Codex Audit" "$SHELL_RC"; then
  TMP="$(mktemp)"
  awk '/# Codex Audit \(added by install\.sh\)/{found=1} found && /^$/{found=0; next} !found' "$SHELL_RC" > "$TMP"
  mv "$TMP" "$SHELL_RC"
fi

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
echo "Add the Codex hook config from plugins/codex-audit/hooks/hooks.json to ~/.codex/hooks.json or <repo>/.codex/hooks.json."
