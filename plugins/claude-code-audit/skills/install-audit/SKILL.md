---
name: install-audit
description: Configure the Claude Code Audit plugin with your server URL, API key, and developer ID
argument-hint: --server <url> --key <api-key> --developer <username>
---

# Install Claude Code Audit

Configure the audit plugin by writing the required environment variables to your shell profile.

## Steps

1. Parse the arguments provided: `--server`, `--key`, `--developer`
2. If any argument is missing, ask the user for it before proceeding
3. Determine the shell config file:
   - Check if `~/.zshrc` exists → use it
   - Else check `~/.bashrc` → use it
   - If neither, tell the user to set the variables manually
4. Remove any existing `# Claude Code Audit` block from the shell config
5. Append the following block to the shell config file:

```
# Claude Code Audit (added by install-audit)
export CLAUDE_AUDIT_SERVER="<server>"
export CLAUDE_AUDIT_API_KEY="<key>"
export CLAUDE_AUDIT_DEVELOPER_ID="<developer>"
```

6. Tell the user:
   - Variables written to `<shell config path>`
   - Run `source <shell config path>` or restart terminal to apply
   - The audit hook will fire automatically after every Claude Code turn

Do NOT write to settings.json — the plugin system registers the hooks automatically via `hooks/hooks.json`.
