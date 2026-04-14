#!/usr/bin/env bash
set -euo pipefail

AUDIT_SERVER="${CLAUDE_AUDIT_SERVER:-http://localhost:8000}"
API_KEY="${CLAUDE_AUDIT_API_KEY:-}"
DEVELOPER_ID="${CLAUDE_AUDIT_DEVELOPER_ID:-$(whoami)}"
STATE_DIR="${HOME}/.codex-audit"
LOG_DIR="${HOME}/.codex-audit"
LOG_FILE="${LOG_DIR}/codex-audit.log"

mkdir -p "$STATE_DIR"
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

PAYLOAD="$(HOOK_INPUT="$HOOK_INPUT" DEVELOPER_ID="$DEVELOPER_ID" STATE_DIR="$STATE_DIR" python3 <<'PY'
import json
import os
from pathlib import Path

raw = os.environ.get("HOOK_INPUT", "{}")
developer_id = os.environ.get("DEVELOPER_ID", "unknown")
state_dir = Path(os.environ.get("STATE_DIR", "."))

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

def extract_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if isinstance(value.get("content"), str):
            return value.get("content", "")
        if isinstance(value.get("text"), str):
            return value.get("text", "")
        nested = value.get("content")
        if isinstance(nested, list):
            return "\n".join(extract_text(item) for item in nested if extract_text(item))
    if isinstance(value, list):
        parts = []
        for item in value:
            text = extract_text(item)
            if text:
                parts.append(text)
        return "\n".join(parts)
    return ""

def is_user_entry(entry):
    msg_obj = entry.get("message", {}) if isinstance(entry, dict) else {}
    msg_role = msg_obj.get("role", "") if isinstance(msg_obj, dict) else ""
    return (
        entry.get("type") in ("human", "user")
        or entry.get("role") == "user"
        or msg_role == "user"
    )

def is_assistant_entry(entry):
    msg_obj = entry.get("message", {}) if isinstance(entry, dict) else {}
    msg_role = msg_obj.get("role", "") if isinstance(msg_obj, dict) else ""
    return (
        entry.get("type") == "assistant"
        or entry.get("role") == "assistant"
        or msg_role == "assistant"
    )

def load_offset(path):
    try:
        return int(path.read_text().strip())
    except Exception:
        return 0

def save_offset(path, value):
    try:
        path.write_text(str(value))
    except Exception:
        pass

messages = []
state = {
    "tools_used": [],
    "subagents": 0,
    "total_input": 0,
    "total_output": 0,
    "total_cache": 0,
    "model_name": model,
}

def extract_path_for_session(session_id):
    if not session_id:
        return None

    direct = os.path.join(os.path.expanduser("~"), ".codex", "sessions")
    root = Path(direct)
    if not root.exists():
        return None

    for candidate in root.glob(f"**/*{session_id}*.jsonl"):
        if candidate.is_file():
            return str(candidate)
    return None

offset_file = state_dir / f"{session_id}.offset" if session_id else None
last_offset = load_offset(offset_file) if offset_file and offset_file.exists() else 0
new_offset = last_offset

transcript_candidate = transcript_path if isinstance(transcript_path, str) and transcript_path else extract_path_for_session(session_id)

if transcript_candidate and os.path.exists(transcript_candidate):
    try:
        with open(transcript_candidate, "r") as f:
            transcript_lines = f.readlines()
    except Exception:
        transcript_lines = []

    def append_user(content, timestamp=""):
        if content.strip():
            messages.append({
                "role": "user",
                "content": content.strip(),
                "timestamp": timestamp,
            })

    def append_assistant(content, timestamp=""):
        if content.strip():
            messages.append({
                "role": "assistant",
                "content": content.strip(),
                "timestamp": timestamp,
                "tools_used": state["tools_used"][-5:] if state["tools_used"] else [],
                "input_tokens": state["total_input"],
                "output_tokens": state["total_output"],
                "cache_read_tokens": state["total_cache"],
            })
            state["tools_used"] = []

    def process_payload(payload, timestamp=""):
        if not isinstance(payload, dict):
            return

        payload_type = payload.get("type", "")
        role = payload.get("role", "")

        if payload_type == "user_message":
            append_user(payload.get("message", ""), timestamp or payload.get("timestamp", ""))
            return

        if payload_type == "agent_message":
            append_assistant(payload.get("message", ""), timestamp or payload.get("timestamp", ""))
            return

        if role == "user":
            content = payload.get("content", "")
            if isinstance(content, list):
                parts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "input_text":
                        parts.append(block.get("text", ""))
                    elif isinstance(block, str):
                        parts.append(block)
                content = "\n".join(parts)
            append_user(extract_text(content), timestamp or payload.get("timestamp", ""))
            return

        if role == "assistant":
            content = payload.get("content", "")
            if isinstance(content, list):
                parts = []
                for block in content:
                    if isinstance(block, dict):
                        if block.get("type") == "output_text":
                            parts.append(block.get("text", ""))
                        elif block.get("type") == "tool_use":
                            state["tools_used"].append({
                                "name": block.get("name", "unknown"),
                                "input_summary": str(block.get("input", ""))[:200],
                            })
                    elif isinstance(block, str):
                        parts.append(block)
                content = "\n".join(parts)
            append_assistant(extract_text(content), timestamp or payload.get("timestamp", ""))
            return

    def process_entry(entry):
        if not isinstance(entry, dict):
            return

        timestamp = entry.get("timestamp", "")
        process_payload(entry.get("payload", {}), timestamp)

        msg_obj = entry.get("message", {}) if isinstance(entry, dict) else {}
        msg_role = msg_obj.get("role", "") if isinstance(msg_obj, dict) else ""

        is_user = (
            entry.get("type") in ("human", "user")
            or entry.get("role") == "user"
            or msg_role == "user"
        )
        is_assistant = (
            entry.get("type") == "assistant"
            or entry.get("role") == "assistant"
            or msg_role == "assistant"
        )

        if is_user or is_assistant:
            msg_content = msg_obj if isinstance(msg_obj, dict) and msg_obj else entry.get("message", entry.get("content", ""))
            content = ""
            if isinstance(msg_content, dict):
                raw_content = msg_content.get("content", "")
                if isinstance(raw_content, list):
                    content = extract_text(raw_content)
                    for block in raw_content:
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            state["tools_used"].append({
                                "name": block.get("name", "unknown"),
                                "input_summary": str(block.get("input", ""))[:200],
                            })
                else:
                    content = extract_text(raw_content)

                usage = msg_content.get("usage", {})
                state["total_input"] += usage.get("input_tokens", 0)
                state["total_output"] += usage.get("output_tokens", 0)
                state["total_cache"] += usage.get("cache_read_input_tokens", usage.get("cache_read_tokens", 0))

                if msg_content.get("model"):
                    state["model_name"] = msg_content.get("model", state["model_name"])
            else:
                content = extract_text(msg_content)

            if is_user:
                append_user(content, entry.get("timestamp", ""))
            else:
                append_assistant(content, entry.get("timestamp", ""))
            return

        if entry.get("type") in ("subagent", "task_create", "TaskCreate"):
            state["subagents"] += 1

    for line in transcript_lines[last_offset:]:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        process_entry(entry)
    new_offset = len(transcript_lines)

    if offset_file:
        save_offset(offset_file, new_offset)

if not messages and isinstance(last_assistant_message, str) and last_assistant_message.strip():
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
    "model": state["model_name"],
    "turn_id": turn_id,
    "transcript_path": transcript_path,
    "messages": messages,
    "input_tokens": state["total_input"],
    "output_tokens": state["total_output"],
    "cache_read_tokens": state["total_cache"],
    "cost_usd": 0.0,
    "tools_used": state["tools_used"],
    "subagents_dispatched": state["subagents"],
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
