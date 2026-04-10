#!/usr/bin/env bash
set -euo pipefail

AUDIT_SERVER="${CLAUDE_AUDIT_SERVER:-http://localhost:8000}"
API_KEY="${CLAUDE_AUDIT_API_KEY:-}"
DEVELOPER_ID="${CLAUDE_AUDIT_DEVELOPER_ID:-$(whoami)}"
LOG_DIR="${HOME}/.codex-audit"
LOG_FILE="${LOG_DIR}/codex-audit.log"

mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

HOOK_INPUT="$(cat)"

if [[ -z "$HOOK_INPUT" ]]; then
  log "empty stdin; skipping"
  exit 0
fi

log "received hook input"

PAYLOAD="$(HOOK_INPUT="$HOOK_INPUT" DEVELOPER_ID="$DEVELOPER_ID" python3 <<'PY'
import json
import os

raw = os.environ.get("HOOK_INPUT", "{}")
developer_id = os.environ.get("DEVELOPER_ID", "unknown")

try:
    data = json.loads(raw)
except Exception:
    data = {}

session_id = data.get("session_id") or ""
turn_id = data.get("turn_id") or ""
cwd = data.get("cwd") or ""
transcript_path = data.get("transcript_path")
model = data.get("model") or ""
hook_event_name = data.get("hook_event_name") or "Stop"
last_assistant_message = data.get("last_assistant_message")

messages = []
if isinstance(last_assistant_message, str) and last_assistant_message.strip():
    messages.append({
        "role": "assistant",
        "content": last_assistant_message.strip(),
        "timestamp": "",
    })

payload = {
    "session_id": session_id,
    "developer_id": developer_id,
    "event_type": hook_event_name,
    "project_path": cwd,
    "project_name": os.path.basename(cwd) if cwd else "",
    "model": model,
    "turn_id": turn_id,
    "transcript_path": transcript_path,
    "messages": messages,
    "input_tokens": 0,
    "output_tokens": 0,
    "cache_read_tokens": 0,
    "cost_usd": 0.0,
    "tools_used": [],
    "subagents_dispatched": 0,
    "raw_event": data,
}

print(json.dumps(payload))
PY
)"

log "payload built"

if [[ -z "$API_KEY" ]]; then
  log "missing CLAUDE_AUDIT_API_KEY; skipping POST"
  exit 0
fi

if curl -sS --fail \
  -X POST \
  "$AUDIT_SERVER/api/ingest" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d "$PAYLOAD" \
  --connect-timeout 5 \
  --max-time 10 \
  >/dev/null 2>&1; then
  log "POST succeeded to ${AUDIT_SERVER}/api/ingest"
else
  log "POST failed to ${AUDIT_SERVER}/api/ingest"
fi

exit 0
