#!/usr/bin/env bash
#
# Codex Audit — Tool Call Hook Script
#
# Fires on PreToolUse ($1=pre) and PostToolUse ($1=post) for every tool call.
# Reads the hook JSON from stdin and POSTs a structured audit record to the
# central audit server.
#
# Environment variables (same as post_turn.sh):
#   AIGW_PROXY_URL      Base URL of the audit server (default: http://localhost:8000)
#   AIGW_PROXY_API_KEY     API key sent as X-Api-Key header
#   CLAUDE_AUDIT_DEVELOPER_ID  Developer identifier (default: whoami)
#

set -euo pipefail

PHASE="${1:-post}"

AUDIT_SERVER="${AIGW_PROXY_URL:-http://localhost:8000}"
API_KEY="${AIGW_PROXY_API_KEY:-}"
DEVELOPER_ID="${CLAUDE_AUDIT_DEVELOPER_ID:-$(whoami)}"

if [ -z "$API_KEY" ]; then
    exit 0  # Not configured — skip silently
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

# Per-tool enrichment: category + key resource fields for audit filtering
tool_category = "unknown"
tool_meta = {}

if tool_name.startswith("mcp__"):
    parts = tool_name.split("__", 2)
    if len(parts) == 3:
        tool_category = "mcp"
        tool_meta["mcp_server"] = parts[1]
        tool_meta["mcp_tool"] = parts[2]
elif tool_name == "Bash":
    tool_category = "code_execution"
    if "command" in tool_input:
        tool_meta["bash_command"] = tool_input["command"]
elif tool_name == "Write":
    tool_category = "file_write"
    if "file_path" in tool_input:
        tool_meta["file_path"] = tool_input["file_path"]
elif tool_name == "Edit":
    tool_category = "file_edit"
    if "file_path" in tool_input:
        tool_meta["file_path"] = tool_input["file_path"]
elif tool_name == "Read":
    tool_category = "file_read"
    if "file_path" in tool_input:
        tool_meta["file_path"] = tool_input["file_path"]
elif tool_name == "Glob":
    tool_category = "file_search"
    if "pattern" in tool_input:
        tool_meta["search_pattern"] = tool_input["pattern"]
    if "path" in tool_input:
        tool_meta["search_path"] = tool_input["path"]
elif tool_name == "Grep":
    tool_category = "file_search"
    if "pattern" in tool_input:
        tool_meta["search_pattern"] = tool_input["pattern"]
    if "path" in tool_input:
        tool_meta["search_path"] = tool_input["path"]
elif tool_name == "WebFetch":
    tool_category = "web"
    if "url" in tool_input:
        tool_meta["web_url"] = tool_input["url"]
elif tool_name == "WebSearch":
    tool_category = "web"
    if "query" in tool_input:
        tool_meta["web_query"] = tool_input["query"]
elif tool_name == "Agent":
    tool_category = "agent"
    if "subagent_type" in tool_input:
        tool_meta["agent_type"] = tool_input["subagent_type"]
    if "description" in tool_input:
        tool_meta["agent_description"] = tool_input["description"]
elif tool_name == "AskUserQuestion":
    tool_category = "interaction"
elif tool_name == "ExitPlanMode":
    tool_category = "planning"

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

if [ -n "$PAYLOAD" ] && [ "$PAYLOAD" != "null" ]; then
    {
        curl -s -X POST \
            "${AUDIT_SERVER}/api/ingest/tool" \
            -H "Content-Type: application/json" \
            -H "X-Api-Key: ${API_KEY}" \
            -d "$PAYLOAD" \
            --connect-timeout 5 \
            --max-time 8 || true
    } </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

exit 0
