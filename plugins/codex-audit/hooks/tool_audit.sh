#!/usr/bin/env bash
#
# Codex Audit — Tool Call Hook Script
#
# Fires on Codex PreToolUse ($1=pre) and PostToolUse ($1=post) for Bash tool
# calls. Reads the hook JSON from stdin and POSTs a structured audit record to
# the central audit server. Mirrors claude-code-audit/hooks/tool_audit.sh.
#
# Environment variables (shared with post_turn.sh):
#   AIGW_PROXY_URL             Base URL of the audit server (default: http://localhost:8000)
#   AIGW_PROXY_API_KEY         API key sent as X-Api-Key header
#   CLAUDE_AUDIT_DEVELOPER_ID  Developer identifier (default: whoami)
#   CODEX_AUDIT_DEBUG          When 1, append debug lines to ~/.codex-audit/codex-audit.log
#

set -euo pipefail

PHASE="${1:-post}"

AUDIT_SERVER="${AIGW_PROXY_URL:-http://localhost:8000}"
API_KEY="${AIGW_PROXY_API_KEY:-}"
DEVELOPER_ID="${CLAUDE_AUDIT_DEVELOPER_ID:-$(whoami)}"
DEBUG="${CODEX_AUDIT_DEBUG:-}"
LOG_FILE="${HOME}/.codex-audit/codex-audit.log"

log() {
    [ "$DEBUG" = "1" ] || return 0
    mkdir -p "${HOME}/.codex-audit" 2>/dev/null || true
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# Config gate: not configured -> skip silently.
if [ -z "$API_KEY" ]; then
    log "missing AIGW_PROXY_API_KEY; skipping"
    exit 0
fi

HOOK_INPUT=$(cat)

export _AUDIT_PHASE="$PHASE"
export DEVELOPER_ID="$DEVELOPER_ID"
export HOOK_INPUT_DATA="$HOOK_INPUT"

PAYLOAD=$(python3 << 'PYEOF'
import json
import os
import sys

phase = os.environ.get("_AUDIT_PHASE", "post")
developer_id = os.environ.get("DEVELOPER_ID", "unknown")
hook_input_raw = os.environ.get("HOOK_INPUT_DATA", "{}")

try:
    data = json.loads(hook_input_raw)
except Exception:
    sys.exit(0)

session_id = data.get("session_id", "")
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {})
tool_use_id = data.get("tool_use_id", "")
cwd = data.get("cwd", "")
model = data.get("model", "")
turn_id = data.get("turn_id", "")
transcript_path = data.get("transcript_path")

# Per-tool enrichment: category + key resource fields for audit filtering.
# Codex emits only Bash today; the full switch is added in Task 2 so records
# are categorized correctly if Codex begins emitting other tool names.
tool_category = "unknown"
tool_meta = {}

if tool_name == "Bash":
    tool_category = "code_execution"
    if "command" in tool_input:
        tool_meta["bash_command"] = tool_input["command"]

tool_output = data.get("tool_response", None) if phase == "post" else None

payload = {
    "session_id": session_id,
    "developer_id": developer_id,
    "event_type": "tool_use",
    "phase": phase,
    "tool_use_id": tool_use_id,
    "tool_name": tool_name,
    "tool_category": tool_category,
    "tool_input": tool_input,
    "tool_output": tool_output,
    "cwd": cwd,
    "model": model,
    "turn_id": turn_id,
}

if isinstance(transcript_path, str) and transcript_path:
    payload["transcript_path"] = transcript_path

payload.update(tool_meta)

print(json.dumps(payload))
PYEOF
)

exit 0
