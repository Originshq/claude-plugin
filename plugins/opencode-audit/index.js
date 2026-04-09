/**
 * OpenCode Audit Plugin
 *
 * Captures session data and POSTs it to a central audit server on every
 * session.idle event. Produces the same payload format as the Claude Code
 * claude-code-audit hook so both can feed the same audit server.
 *
 * Environment variables (same as the Claude Code plugin):
 *   CLAUDE_AUDIT_SERVER       Base URL of your audit server (default: http://localhost:8000)
 *   CLAUDE_AUDIT_API_KEY      API key sent as X-Api-Key header (required)
 *   CLAUDE_AUDIT_DEVELOPER_ID Developer identifier included in every payload (default: $USER)
 *
 * Installation:
 *   Project-level:  copy to .opencode/plugins/opencode-audit.js
 *   Global:         copy to ~/.config/opencode/plugins/opencode-audit.js
 */

export const OpenCodeAuditPlugin = async ({ client }) => {
  const AUDIT_SERVER = process.env.CLAUDE_AUDIT_SERVER ?? "http://localhost:8000"
  const API_KEY = process.env.CLAUDE_AUDIT_API_KEY ?? ""
  const DEVELOPER_ID =
    process.env.CLAUDE_AUDIT_DEVELOPER_ID ?? process.env.USER ?? "unknown"

  // Per-session accumulated state
  const sessions = new Map()

  function getSession(sessionId) {
    if (!sessions.has(sessionId)) {
      sessions.set(sessionId, {
        messages: [],
        inputTokens: 0,
        outputTokens: 0,
        cacheTokens: 0,
        model: "",
        projectPath: "",
        projectName: "",
      })
    }
    return sessions.get(sessionId)
  }

  function extractContent(msg) {
    const content = msg.content ?? msg.Content
    if (!content) return ""
    if (typeof content === "string") return content.trim()
    if (Array.isArray(content)) {
      return content
        .filter((b) => typeof b === "string" || (b && b.type === "text"))
        .map((b) => (typeof b === "string" ? b : (b.text ?? "")))
        .join("\n")
        .trim()
    }
    return ""
  }

  return {
    event: async ({ event }) => {
      const props = event.properties ?? event

      // ── Accumulate messages as they arrive ───────────────────────────────
      if (event.type === "message.updated") {
        const sessionId =
          props.sessionID ?? props.session_id ?? props.sessionId
        if (!sessionId) return

        const state = getSession(sessionId)

        // Capture project info if available
        if (props.projectPath && !state.projectPath)
          state.projectPath = props.projectPath
        if (props.projectName && !state.projectName)
          state.projectName = props.projectName

        const msg = props.message ?? props
        const role = msg.role ?? msg.Role
        if (!role) return

        const content = extractContent(msg)
        if (!content) return

        // Deduplicate: skip if last message is identical
        const last = state.messages[state.messages.length - 1]
        if (last && last.role === role && last.content === content) return

        // Token usage from assistant turns
        if (role === "assistant") {
          const usage = msg.usage ?? msg.Usage ?? {}
          state.inputTokens +=
            usage.inputTokens ?? usage.input_tokens ?? 0
          state.outputTokens +=
            usage.outputTokens ?? usage.output_tokens ?? 0
          state.cacheTokens +=
            usage.cacheReadInputTokens ??
            usage.cache_read_tokens ??
            0
          if (msg.model ?? msg.Model) state.model = msg.model ?? msg.Model
        }

        state.messages.push({
          role,
          content,
          timestamp: props.time ?? new Date().toISOString(),
        })
      }

      // ── POST on session idle (equivalent to Claude Code Stop event) ───────
      if (event.type === "session.idle") {
        const sessionId =
          props.sessionID ?? props.session_id ?? props.sessionId
        if (!sessionId) return
        if (!API_KEY) return

        const state = sessions.get(sessionId)
        if (!state || state.messages.length === 0) return

        const payload = {
          session_id: sessionId,
          developer_id: DEVELOPER_ID,
          event_type: "session.idle",
          project_path: state.projectPath || (props.projectPath ?? ""),
          project_name: state.projectName || (props.projectName ?? ""),
          model: state.model || (props.model ?? ""),
          messages: state.messages,
          input_tokens: state.inputTokens,
          output_tokens: state.outputTokens,
          cache_read_tokens: state.cacheTokens,
          cost_usd: 0.0,
          tools_used: [],
          subagents_dispatched: 0,
          raw_event: event,
        }

        // Fire-and-forget — never block OpenCode
        fetch(`${AUDIT_SERVER}/api/ingest`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Api-Key": API_KEY,
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(10_000),
        }).catch(() => {})

        sessions.delete(sessionId)
      }
    },
  }
}
