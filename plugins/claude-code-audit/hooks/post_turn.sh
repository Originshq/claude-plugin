#!/usr/bin/env bash
#
# Claude Code Audit — Hook Script
# 
# This script fires on Claude Code "Stop" events. It reads the
# session JSONL log, extracts new messages, and POSTs them to
# the central audit server.
#
# SETUP:
#   1. Copy this file to ~/.claude/hooks/post_turn.sh
#   2. chmod +x ~/.claude/hooks/post_turn.sh
#   3. Set environment variables (add to ~/.bashrc or ~/.zshrc):
#        export AIGW_PROXY_URL="https://your-audit-server.example.com"
#        export AIGW_PROXY_API_KEY="cca_your_key_here"
#        export CLAUDE_AUDIT_DEVELOPER_ID="your-username"
#   4. Run: claude-code-audit-install (or manually add hook config)
#

set -euo pipefail

# ─── Config ───
AUDIT_SERVER="${AIGW_PROXY_URL:-http://localhost:8000}"
API_KEY="${AIGW_PROXY_API_KEY:-}"
DEVELOPER_ID="${CLAUDE_AUDIT_DEVELOPER_ID:-$(whoami)}"
STATE_DIR="${HOME}/.claude-audit"
mkdir -p "$STATE_DIR"

# ─── Read hook event from stdin ───
HOOK_INPUT=$(cat)

# Extract key fields from the hook JSON
SESSION_ID=$(echo "$HOOK_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session_id', data.get('sessionId', '')))" 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
    exit 0  # No session ID, skip
fi

if [ -z "$API_KEY" ]; then
    echo "[claude-audit] ERROR: AIGW_PROXY_API_KEY not set" >&2
    exit 0  # Don't block Claude Code
fi

# ─── Find the session JSONL file ───
# Claude Code stores sessions in ~/.claude/projects/<project-hash>/<session-id>.jsonl
JSONL_FILE=""
for f in "${HOME}"/.claude/projects/*/"${SESSION_ID}.jsonl"; do
    if [ -f "$f" ]; then
        JSONL_FILE="$f"
        break
    fi
done

# Also check direct sessions dir
if [ -z "$JSONL_FILE" ] && [ -f "${HOME}/.claude/sessions/${SESSION_ID}.jsonl" ]; then
    JSONL_FILE="${HOME}/.claude/sessions/${SESSION_ID}.jsonl"
fi

if [ -z "$JSONL_FILE" ]; then
    # Fall back to just sending the hook event itself
    JSONL_FILE=""
fi

# ─── Track what we've already sent ───
OFFSET_FILE="${STATE_DIR}/${SESSION_ID}.offset"
LAST_OFFSET=0
if [ -f "$OFFSET_FILE" ]; then
    LAST_OFFSET=$(cat "$OFFSET_FILE")
fi

# Export vars so the Python heredoc can read them
export SESSION_ID
export JSONL_FILE
export LAST_OFFSET
export DEVELOPER_ID
export HOOK_INPUT_DATA="$HOOK_INPUT"

# ─── Extract new messages from JSONL ───
# Claude Code JSONL format has entries with type, role, content, etc.
PAYLOAD=$(python3 << 'PYEOF'
import json
import os
import sys

session_id = os.environ.get("SESSION_ID", "")
jsonl_file = os.environ.get("JSONL_FILE", "")
last_offset = int(os.environ.get("LAST_OFFSET", "0"))
developer_id = os.environ.get("DEVELOPER_ID", "unknown")
hook_input = os.environ.get("HOOK_INPUT_DATA", "{}")

try:
    hook_data = json.loads(hook_input)
except:
    hook_data = {}

messages = []
new_offset = last_offset
project_path = ""
project_name = ""
model = ""
total_input = 0
total_output = 0
total_cache = 0
total_cost = 0.0
tools_used = []
subagents = 0

if jsonl_file and os.path.exists(jsonl_file):
    # Derive project path from JSONL location
    parts = jsonl_file.split("/")
    if "projects" in parts:
        idx = parts.index("projects")
        if idx + 1 < len(parts):
            project_path = parts[idx + 1]  # hashed project path

    with open(jsonl_file, "r") as f:
        lines = f.readlines()

    new_offset = len(lines)

    # Process only new lines
    for line in lines[last_offset:]:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except:
            continue

        entry_type = entry.get("type", "")

        # Extract user messages
        msg_obj = entry.get("message", {})
        msg_role = msg_obj.get("role", "") if isinstance(msg_obj, dict) else ""
        if entry_type in ("human", "user") or entry.get("role") == "user" or msg_role == "user":
            content = ""
            msg_content = msg_obj.get("content", "") if isinstance(msg_obj, dict) else entry.get("content", "")
            if isinstance(msg_content, str):
                content = msg_content
            elif isinstance(msg_content, dict):
                content = msg_content.get("content", str(msg_content))
            elif isinstance(msg_content, list):
                # Content blocks
                parts_text = []
                for block in msg_content:
                    if isinstance(block, str):
                        parts_text.append(block)
                    elif isinstance(block, dict) and block.get("type") == "text":
                        parts_text.append(block.get("text", ""))
                content = "\n".join(parts_text)

            if content.strip():
                messages.append({
                    "role": "user",
                    "content": content.strip(),
                    "timestamp": entry.get("timestamp", ""),
                })

        # Extract assistant messages
        elif entry_type == "assistant" or entry.get("role") == "assistant" or msg_role == "assistant":
            content = ""
            msg_content = msg_obj if isinstance(msg_obj, dict) and msg_obj else entry.get("message", entry.get("content", ""))
            if isinstance(msg_content, str):
                content = msg_content
            elif isinstance(msg_content, dict):
                # Could have content blocks
                raw = msg_content.get("content", "")
                if isinstance(raw, list):
                    text_parts = []
                    for block in raw:
                        if isinstance(block, dict):
                            if block.get("type") == "text":
                                text_parts.append(block.get("text", ""))
                            elif block.get("type") == "tool_use":
                                tools_used.append({
                                    "name": block.get("name", "unknown"),
                                    "input_summary": str(block.get("input", ""))[:200],
                                })
                    content = "\n".join(text_parts)
                elif isinstance(raw, str):
                    content = raw

                # Token usage
                usage = msg_content.get("usage", {})
                total_input += usage.get("input_tokens", 0)
                total_output += usage.get("output_tokens", 0)
                total_cache += usage.get("cache_read_input_tokens", usage.get("cache_read_tokens", 0))

                # Model
                m = msg_content.get("model", "")
                if m:
                    model = m

            if content.strip():
                messages.append({
                    "role": "assistant",
                    "content": content.strip(),
                    "timestamp": entry.get("timestamp", ""),
                    "tools_used": tools_used[-5:] if tools_used else [],  # last 5
                    "input_tokens": total_input,
                    "output_tokens": total_output,
                    "cache_read_tokens": total_cache,
                })
                tools_used = []  # reset for next turn

        # Count subagent dispatches
        elif entry_type in ("subagent", "task_create", "TaskCreate"):
            subagents += 1

# Build payload
payload = {
    "session_id": session_id,
    "developer_id": developer_id,
    "event_type": hook_data.get("type", hook_data.get("hook_type", "Stop")),
    "project_path": project_path,
    "project_name": project_name or os.path.basename(project_path) if project_path else None,
    "model": model or hook_data.get("model", None),
    "messages": messages,
    "input_tokens": total_input,
    "output_tokens": total_output,
    "cache_read_tokens": total_cache,
    "cost_usd": 0.0,  # computed server-side or by hook enhancement
    "tools_used": tools_used,
    "subagents_dispatched": subagents,
    "raw_event": hook_data,
}

print(json.dumps(payload))
# Write new offset to stderr so we can capture it
print(str(new_offset), file=sys.stderr)

PYEOF
) 2>"${STATE_DIR}/${SESSION_ID}.new_offset"

# Update offset
if [ -f "${STATE_DIR}/${SESSION_ID}.new_offset" ]; then
    NEW_OFFSET=$(cat "${STATE_DIR}/${SESSION_ID}.new_offset")
    if [ -n "$NEW_OFFSET" ] && [ "$NEW_OFFSET" -gt "$LAST_OFFSET" ] 2>/dev/null; then
        echo "$NEW_OFFSET" > "$OFFSET_FILE"
    fi
    rm -f "${STATE_DIR}/${SESSION_ID}.new_offset"
fi

# ─── POST to audit server ───
if [ -n "$PAYLOAD" ] && [ "$PAYLOAD" != "null" ]; then
    LOG_FILE="${STATE_DIR}/requests-$(date +%Y-%m-%d).log"
    {
        echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") session=${SESSION_ID} ==="
        echo "POST ${AUDIT_SERVER}/api/ingest"
        echo "$PAYLOAD" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null || echo "$PAYLOAD"
        echo ""
    } >> "$LOG_FILE"

    curl -s -X POST \
        "${AUDIT_SERVER}/api/ingest" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: ${API_KEY}" \
        -d "$PAYLOAD" \
        --connect-timeout 5 \
        --max-time 10 \
        >/dev/null 2>&1 || true  # Never block Claude Code
fi

exit 0
