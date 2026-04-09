# Claude Code Audit — OpenCode Plugin

OpenCode equivalent of the `claude-code-audit` Claude Code plugin.
It hooks into OpenCode's event system to capture session data and POST it to a central audit server.

The payload format is **identical** to the Claude Code plugin, so both can feed the same audit server.

---

## Installation

### 1. Copy the plugin

**Project-level** (this project only):

```bash
mkdir -p .opencode/plugins
cp plugins/opencode-audit/index.js .opencode/plugins/opencode-audit.js
```

**Global** (all projects):

```bash
mkdir -p ~/.config/opencode/plugins
cp plugins/opencode-audit/index.js ~/.config/opencode/plugins/opencode-audit.js
```

OpenCode loads all `.js` / `.ts` files from these directories automatically at startup — no further config needed.

---

### 2. Configure credentials

**Option A — run the existing install script** (writes exports to `~/.zshrc` or `~/.bashrc`):

```bash
bash plugins/claude-code-audit/hooks/install.sh \
  --server https://your-audit-server.example.com \
  --key cca_your_key_here \
  --developer your-username
```

**Option B — add to your shell profile manually**:

```bash
export CLAUDE_AUDIT_SERVER="https://your-audit-server.example.com"
export CLAUDE_AUDIT_API_KEY="cca_your_key_here"
export CLAUDE_AUDIT_DEVELOPER_ID="your-username"
```

---

### 3. Reload your shell

```bash
source ~/.zshrc   # or ~/.bashrc
```

The audit plugin is now active. Every `session.idle` event will POST session data to your audit server.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CLAUDE_AUDIT_SERVER` | Yes | `http://localhost:8000` | Base URL of your audit server |
| `CLAUDE_AUDIT_API_KEY` | Yes | — | API key sent as `X-Api-Key` header |
| `CLAUDE_AUDIT_DEVELOPER_ID` | No | `$USER` | Developer identifier in every payload |

---

## How it works

| Step | What happens |
|---|---|
| `message.updated` event | Plugin accumulates messages and token usage in memory, keyed by session ID |
| `session.idle` event | Plugin POSTs the accumulated payload to `${CLAUDE_AUDIT_SERVER}/api/ingest` and clears state |
| Errors | All fetch errors are silently swallowed — the plugin never blocks OpenCode |

---

## Differences from the Claude Code plugin

| | Claude Code | OpenCode |
|---|---|---|
| Plugin format | Bash hook script | JavaScript/ES module |
| Trigger event | `Stop` / `SubagentStop` | `session.idle` |
| Data source | JSONL files on disk (`~/.claude/projects/…`) | In-memory event accumulation |
| Offset tracking | File-based (`~/.claude-audit/<id>.offset`) | Not needed — state cleared after each POST |
| Installation | `/plugin` marketplace | Copy file to plugins directory |
| Config | Same env vars | Same env vars |

---

## API payload format

```json
{
  "session_id": "abc123",
  "developer_id": "alice",
  "event_type": "session.idle",
  "project_path": "my-project",
  "project_name": "my-project",
  "model": "claude-sonnet-4-6",
  "messages": [
    { "role": "user",      "content": "…", "timestamp": "…" },
    { "role": "assistant", "content": "…", "timestamp": "…" }
  ],
  "input_tokens": 1234,
  "output_tokens": 567,
  "cache_read_tokens": 89,
  "cost_usd": 0.0,
  "tools_used": [],
  "subagents_dispatched": 0,
  "raw_event": {}
}
```
