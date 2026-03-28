# Claude Code Audit — Local Plugin Marketplace

A local Claude Code plugin marketplace containing the `claude-code-audit` plugin.

## Installation

### 1. Add the marketplace

Inside a Claude Code session:

```
/plugin marketplace add https://github.com/Originshq/claude-plugin.git
```

Or to make it available across all projects, add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-audit-marketplace": {
      "source": {
        "source": "github",
        "repo": "Originshq/claude-plugin"
      }
    }
  }
}
```

### 2. Install the plugin

```
/plugin install claude-code-audit@claude-code-audit-marketplace
```

### 3. Configure credentials

Run the `/install-audit` slash command in Claude Code:

```
/install-audit --server https://your-audit-server.example.com --key cca_your_key_here --developer your-username
```

This writes the following exports to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Claude Code Audit (added by install-audit)
export CLAUDE_AUDIT_SERVER="https://your-audit-server.example.com"
export CLAUDE_AUDIT_API_KEY="cca_your_key_here"
export CLAUDE_AUDIT_DEVELOPER_ID="your-username"
```

Restart your terminal or run `source ~/.zshrc` to apply.


## Quick start

**Step 1 — Clone this repo**

```bash
git clone https://github.com/Originshq/claude-plugin.git ~/claude-plugin
```

**Step 2 — Add the marketplace to Claude Code**

Inside a Claude Code session, run:

```
/plugin marketplace add ~/claude-plugin
```

Or add it to `~/.claude/settings.json` to persist across projects:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-audit-marketplace": {
      "source": {
        "source": "github",
        "repo": "Originshq/claude-plugin"
      }
    }
  }
}
```

**Step 3 — Install the plugin**

```
/plugin install claude-code-audit@claude-code-audit-marketplace
```

**Step 4 — Configure your audit server credentials**

Run this slash command inside any Claude Code session:

```
/install-audit --server https://your-audit-server.example.com --key cca_your_key_here --developer your-username
```

**Step 5 — Reload your shell**

```bash
source ~/.zshrc   # or ~/.bashrc
```

The audit hook is now active. Every Claude Code turn will be posted to your audit server automatically.

---

## What it does

`claude-code-audit` hooks into Claude Code's `Stop` and `SubagentStop` events to capture every conversation turn and POST the session data to a central audit server. This gives teams visibility into AI-assisted development activity for compliance, review, and cost tracking.

Each audit payload includes:

- Session and project metadata
- Full user/assistant message history (new turns only, via offset tracking)
- Tool calls made during the turn
- Token usage (input, output, cache read)
- Model identifier
- Subagent dispatch count

## Repository structure

```
plugin/
├── README.md
├── .claude-plugin/
│   └── marketplace.json          # Marketplace registry
└── plugins/
    └── claude-code-audit/
        ├── .claude-plugin/
        │   └── plugin.json       # Plugin metadata
        ├── hooks/
        │   ├── hooks.json        # Hook registrations (Stop + SubagentStop)
        │   └── post_turn.sh      # Hook script — reads JSONL, builds payload, POSTs
        └── skills/
            └── install-audit/
                └── SKILL.md      # /install-audit slash command
```

## Prerequisites

- Claude Code CLI installed
- An audit server exposing `POST /api/ingest` (accepts `X-Api-Key` header)
- `bash`, `python3`, and `curl` available in your shell

## Installation

### 1. Add the marketplace

Inside a Claude Code session:

```
/plugin marketplace add https://github.com/Originshq/claude-plugin.git
```

Or to make it available across all projects, add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-code-audit-marketplace": {
      "source": {
        "source": "github",
        "repo": "Originshq/claude-plugin"
      }
    }
  }
}
```

### 2. Install the plugin

```
/plugin install claude-code-audit@claude-code-audit-marketplace
```

### 3. Configure credentials

Run the `/install-audit` slash command in Claude Code:

```
/install-audit --server https://your-audit-server.example.com --key cca_your_key_here --developer your-username
```

This writes the following exports to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Claude Code Audit (added by install-audit)
export CLAUDE_AUDIT_SERVER="https://your-audit-server.example.com"
export CLAUDE_AUDIT_API_KEY="cca_your_key_here"
export CLAUDE_AUDIT_DEVELOPER_ID="your-username"
```

Restart your terminal or run `source ~/.zshrc` to apply.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CLAUDE_AUDIT_SERVER` | Yes | `http://localhost:8000` | Base URL of your audit server |
| `CLAUDE_AUDIT_API_KEY` | Yes | — | API key sent as `X-Api-Key` header |
| `CLAUDE_AUDIT_DEVELOPER_ID` | No | `$(whoami)` | Developer identifier included in every payload |

## How the hook works

On every `Stop` or `SubagentStop` event:

1. Reads the hook JSON from stdin to get `session_id`
2. Locates the session JSONL file at `~/.claude/projects/<hash>/<session_id>.jsonl`
3. Reads only **new lines** since the last run (offset tracked in `~/.claude-audit/<session_id>.offset`)
4. Extracts user messages, assistant messages, tool calls, and token usage
5. POSTs a JSON payload to `${CLAUDE_AUDIT_SERVER}/api/ingest`
6. Never blocks Claude Code — all errors are silently swallowed

## API payload format

```json
{
  "session_id": "abc123",
  "developer_id": "alice",
  "event_type": "Stop",
  "project_path": "<hashed-project-dir>",
  "project_name": "<basename>",
  "model": "claude-sonnet-4-6",
  "messages": [
    {
      "role": "user",
      "content": "...",
      "timestamp": "..."
    },
    {
      "role": "assistant",
      "content": "...",
      "timestamp": "...",
      "tools_used": [{ "name": "Bash", "input_summary": "..." }],
      "input_tokens": 1234,
      "output_tokens": 567,
      "cache_read_tokens": 89
    }
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

## State files

The hook stores per-session offset files in `~/.claude-audit/` to avoid re-sending messages already sent in a previous turn.

```
~/.claude-audit/
└── <session_id>.offset   # Line count of last successful POST
```
