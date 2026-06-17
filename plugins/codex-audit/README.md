# Codex Audit

Codex Audit is a plugin that captures every tool call, user prompt, and conversation turn in Codex and posts structured audit records to a central server for team visibility and compliance.

## What it includes

| File | Purpose |
|------|---------|
| `.codex-plugin/plugin.json` | Plugin manifest — declares the plugin and points Codex to `hooks/hooks.json` |
| `hooks/hooks.json` | Hook config used in plugin mode (paths resolved via `$PLUGIN_ROOT`) |
| `hooks/tool_audit.sh` | Handles `SessionStart`, `PreToolUse`, `PostToolUse`, and `UserPromptSubmit` events |
| `hooks/post_turn.sh` | Handles the `Stop` event — reads the session transcript and posts a full turn record |
| `hooks/install.sh` | Manual (non-plugin) installer — copies scripts to `~/.codex/` and writes env vars to your shell rc |

## Hook events

| Event | Matcher | What gets captured |
|-------|---------|-------------------|
| `SessionStart` | `startup\|resume\|clear\|compact` | Session source, cwd, model, permission mode |
| `PreToolUse` | `.*` (all tools) | Tool name, category, inputs before execution |
| `PostToolUse` | `.*` (all tools) | Tool name, category, inputs, and tool output |
| `UserPromptSubmit` | — (not filterable) | Raw user prompt text |
| `Stop` | — (not filterable) | Full turn transcript, token counts, tools used |

## Tool categories

`tool_audit.sh` classifies every tool call into a category for easier filtering:

| Category | Tools |
|----------|-------|
| `code_execution` | `Bash` |
| `file_edit` | `apply_patch` (also matched via `Edit`/`Write` aliases) |
| `file_write` | `Write` |
| `file_read` | `Read` |
| `file_search` | `Glob`, `Grep` |
| `web` | `WebFetch`, `WebSearch` |
| `agent` | `Agent` |
| `interaction` | `AskUserQuestion` |
| `planning` | `ExitPlanMode` |
| `mcp` | Any `mcp__<server>__<tool>` call |
| `unknown` | Anything else |

## Deployment: plugin mode (recommended)

Enable the plugin from your Codex plugin directory. Codex sets `$PLUGIN_ROOT` automatically so no path configuration is needed. After enabling, open `/hooks` in the Codex CLI to review and trust the hook definitions before they run.

Set the required environment variables in your shell:

```bash
export AIGW_PROXY_URL="https://your-audit-server.example.com"
export AIGW_PROXY_API_KEY="your_api_key"
export CLAUDE_AUDIT_DEVELOPER_ID="your-username"   # defaults to $(whoami)
```

## Deployment: manual install

Run the installer once per machine:

```bash
bash plugins/codex-audit/hooks/install.sh
```

The installer:
1. Enables `hooks = true` under `[features]` in `~/.codex/config.toml`
2. Copies `tool_audit.sh` and `post_turn.sh` to `~/.codex/`
3. Writes a `~/.codex/hooks.json` covering all five hook events (skipped if one already exists — see the merge warning)

Then run `source ~/.zshrc` (or `~/.bashrc`) and restart Codex.

## API endpoints

| Endpoint | Event |
|----------|-------|
| `POST /api/ingest/session` | `SessionStart` |
| `POST /api/ingest/prompt` | `UserPromptSubmit` |
| `POST /api/ingest/tool` | `PreToolUse` / `PostToolUse` |
| `POST /api/ingest` | `Stop` (full turn record) |

All requests carry an `X-Api-Key` header and a JSON body. Tool calls fire asynchronously (backgrounded curl) to avoid blocking the agent loop. The `Stop` handler is synchronous with a 30-second timeout.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AIGW_PROXY_URL` | `http://localhost:8000` | Base URL of the audit server |
| `AIGW_PROXY_API_KEY` | *(required)* | API key sent as `X-Api-Key` |
| `CLAUDE_AUDIT_DEVELOPER_ID` | `$(whoami)` | Developer identifier included in every payload |

If `AIGW_PROXY_API_KEY` is not set, all hooks exit silently without posting.

## Debug logs

The `Stop` handler writes to `~/.codex-audit/codex-audit.log`:

```
[2026-06-17T10:00:00Z] received hook input
[2026-06-17T10:00:01Z] payload built
[2026-06-17T10:00:01Z] POST succeeded to https://your-audit-server.example.com/api/ingest
```
