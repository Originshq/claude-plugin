# Codex Audit

Codex Audit is a local plugin package that mirrors the existing Claude Code audit workflow for Codex hook events.

## What it includes

- `.codex-plugin/plugin.json` plugin manifest
- `hooks/hooks.json` Codex hook config template
- `hooks/install.sh` environment variable helper
- `hooks/post_turn.sh` audit POST script

## Setup

1. Set the audit server credentials:

```bash
bash plugins/codex-audit/hooks/install.sh \
  --server https://your-audit-server.example.com \
  --key cca_your_key_here \
  --developer your-username
```

2. Add the hook config to either `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`.

3. Copy `plugins/codex-audit/hooks/post_turn.sh` to `~/.codex/post_turn.sh`.

4. Restart Codex.

The hook posts turn data to `${CLAUDE_AUDIT_SERVER}/api/ingest` using the same environment variables as the Claude Code audit plugin.

Debug logs are written to `~/.codex-audit/codex-audit.log`.
