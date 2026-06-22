# Claude Code Audit — OpenCode Plugin

OpenCode equivalent of the `claude-code-audit` / `codex-audit` plugins.
It hooks into OpenCode's event system to capture session data **and every tool call (input + output)**, posting structured audit records to a central audit server.

The payload format is **identical** to the codex-audit plugin so both can feed the same audit server.

---

## Installation

### 1. Copy the plugin


**Global** (all projects):

```bash
mkdir -p ~/.config/opencode/plugins
cp plugins/opencode-audit/index.js ~/.config/opencode/plugins/opencode-audit.js
```


**Project-level** (this project only):

```bash
mkdir -p .opencode/plugins
cp plugins/opencode-audit/index.js .opencode/plugins/opencode-audit.js
```

OpenCode loads all `.js` / `.ts` files from these directories automatically at startup — no further config needed.

---

### 2. Configure credentials

Add the following exports to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
export AIGW_PROXY_URL="https://your-audit-server.example.com"
export AIGW_PROXY_API_KEY="cca_your_key_here"
export CLAUDE_AUDIT_DEVELOPER_ID="your-username"
```

---

### 3. Reload your shell

```bash
source ~/.zshrc   # or ~/.bashrc
```

The audit plugin is now active. Session start, every tool call, and every `session.idle` event will be posted to your audit server.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AIGW_PROXY_URL` | Yes | `http://localhost:8000` | Base URL of your audit server |
| `AIGW_PROXY_API_KEY` | Yes | — | API key sent as `X-Api-Key` header |
| `CLAUDE_AUDIT_DEVELOPER_ID` | No | `$USER` | Developer identifier included in every payload |

---

## How it works

| Step | Event / Hook | What happens |
|---|---|---|
| Session starts | `session.created` | POSTs a `session_start` record to `/api/ingest/session` |
| Before each tool call | `tool.execute.before` | POSTs a `tool_use` record (`phase: "pre"`) to `/api/ingest/tool` with the tool name, category, and input args |
| After each tool call | `tool.execute.after` | POSTs a `tool_use` record (`phase: "post"`) to `/api/ingest/tool` with the tool output |
| Messages accumulate | `message.updated` / `message.part.updated` | Plugin accumulates messages and token usage in memory, keyed by session ID |
| Session goes idle | `session.idle` | POSTs the full accumulated session summary to `/api/ingest` and clears in-memory state |
| Errors | — | All fetch errors are silently swallowed — the plugin never blocks OpenCode |

---

## Tool categorization

The plugin categorises every tool call the same way as the codex-audit `tool_audit.sh`:

| Category | Tools |
|---|---|
| `code_execution` | `bash` |
| `file_read` | `read` |
| `file_write` | `write` |
| `file_edit` | `edit`, `apply_patch` |
| `file_search` | `glob`, `grep` |
| `web` | `webfetch`, `websearch` |
| `mcp` | any `mcp__<server>__<tool>` |
| `agent` | `agent` |
| `interaction` | `askuserquestion` |
| `planning` | `exitplanmode` |

---

## API payload formats

### Session start — `POST /api/ingest/session`

```json
{
  "session_id": "abc123",
  "developer_id": "alice",
  "event_type": "session_start",
  "cwd": "/home/alice/my-project",
  "project_path": "/home/alice/my-project",
  "project_name": "my-project"
}
```

### Tool event — `POST /api/ingest/tool`

```json
{
  "session_id": "abc123",
  "developer_id": "alice",
  "event_type": "tool_use",
  "phase": "pre",
  "tool_name": "bash",
  "tool_category": "code_execution",
  "tool_input": { "command": "npm test" },
  "tool_output": null,
  "cwd": "/home/alice/my-project",
  "bash_command": "npm test"
}
```

`phase` is `"pre"` before execution and `"post"` after. On `"post"`, `tool_output` contains the tool result.

### Session idle summary — `POST /api/ingest`

```json
{
  "session_id": "abc123",
  "developer_id": "alice",
  "event_type": "session.idle",
  "project_path": "/home/alice/my-project",
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

---

## Differences from the codex-audit plugin

| | codex-audit | opencode-audit |
|---|---|---|
| Plugin format | Bash hook script | JavaScript/ES module |
| Trigger | `PreToolUse` / `PostToolUse` / `SessionStart` hooks | `tool.execute.before` / `tool.execute.after` / `session.created` events |
| Session summary trigger | `Stop` / `SubagentStop` | `session.idle` |
| Data source | `stdin` JSON from the hook harness | In-memory event accumulation |
| Offset tracking | File-based (`~/.claude-audit/<id>.offset`) | Not needed — state cleared after each POST |
| Installation | `/plugin` marketplace | Copy file to plugins directory |
| Env vars | Same (`AIGW_PROXY_URL`, `AIGW_PROXY_API_KEY`, `CLAUDE_AUDIT_DEVELOPER_ID`) | Same |
