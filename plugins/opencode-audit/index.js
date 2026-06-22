import { appendFile } from "node:fs/promises"

/**
 * OpenCode Audit Plugin
 *
 * Captures session data and tool input/output, POSTing structured audit records
 * to a central audit server. Mirrors the codex-audit tool_audit.sh behaviour so
 * both plugins can feed the same audit server.
 *
 * Environment variables (same as the codex-audit plugin):
 *   AIGW_PROXY_URL            Base URL of the audit server (default: http://localhost:8000)
 *   AIGW_PROXY_API_KEY        API key sent as X-Api-Key header (required)
 *   CLAUDE_AUDIT_DEVELOPER_ID Developer identifier included in every payload (default: $USER)
 *
 * Endpoints used:
 *   POST /api/ingest/session  — session start
 *   POST /api/ingest/tool     — tool pre/post events
 *   POST /api/ingest          — session idle summary
 *
 * Installation:
 *   Project-level:  copy to .opencode/plugins/opencode-audit.js
 *   Global:         copy to ~/.config/opencode/plugins/opencode-audit.js
 */

export const OpenCodeAuditPlugin = async ({ project, directory }) => {
  const LOG_FILE = new URL("./opencode-audit.log", import.meta.url)
  const AUDIT_SERVER = process.env.AIGW_PROXY_URL ?? "http://localhost:8000"
  const API_KEY = process.env.AIGW_PROXY_API_KEY ?? ""
  const DEVELOPER_ID =
    process.env.CLAUDE_AUDIT_DEVELOPER_ID ?? process.env.USER ?? "unknown"

  const sessions = new Map()

  async function log(message) {
    const line = `[${new Date().toISOString()}] ${message}\n`
    try {
      await appendFile(LOG_FILE, line)
    } catch {
      // Logging must never interfere with the plugin.
    }
  }

  void log("plugin initialized")

  function postAudit(endpoint, payload) {
    if (!API_KEY) return
    fetch(`${AUDIT_SERVER}${endpoint}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Api-Key": API_KEY,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    })
      .then((res) => void log(`POST ${endpoint} status=${res.status}`))
      .catch((err) =>
        void log(
          `POST ${endpoint} failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      )
  }

  function categorizeTool(toolName, toolArgs) {
    let category = "unknown"
    const meta = {}
    const name = toolName ?? ""

    if (name.startsWith("mcp__")) {
      const parts = name.split("__", 3)
      if (parts.length === 3) {
        category = "mcp"
        meta.mcp_server = parts[1]
        meta.mcp_tool = parts[2]
      }
    } else if (name === "bash") {
      category = "code_execution"
      if (toolArgs?.command) meta.bash_command = toolArgs.command
    } else if (name === "apply_patch") {
      category = "file_edit"
      if (toolArgs?.command) meta.patch_command = String(toolArgs.command).slice(0, 500)
    } else if (name === "write") {
      category = "file_write"
      if (toolArgs?.filePath) meta.file_path = toolArgs.filePath
    } else if (name === "edit") {
      category = "file_edit"
      if (toolArgs?.filePath) meta.file_path = toolArgs.filePath
    } else if (name === "read") {
      category = "file_read"
      if (toolArgs?.filePath) meta.file_path = toolArgs.filePath
    } else if (name === "glob") {
      category = "file_search"
      if (toolArgs?.pattern) meta.search_pattern = toolArgs.pattern
      if (toolArgs?.path) meta.search_path = toolArgs.path
    } else if (name === "grep") {
      category = "file_search"
      if (toolArgs?.pattern) meta.search_pattern = toolArgs.pattern
      if (toolArgs?.path) meta.search_path = toolArgs.path
    } else if (name === "webfetch") {
      category = "web"
      if (toolArgs?.url) meta.web_url = toolArgs.url
    } else if (name === "websearch") {
      category = "web"
      if (toolArgs?.query) meta.web_query = toolArgs.query
    } else if (name === "agent") {
      category = "agent"
      if (toolArgs?.subagent_type) meta.agent_type = toolArgs.subagent_type
      if (toolArgs?.description) meta.agent_description = toolArgs.description
    } else if (name === "askuserquestion") {
      category = "interaction"
    } else if (name === "exitplanmode") {
      category = "planning"
    }

    return { category, meta }
  }

  function getSession(sessionId) {
    if (!sessions.has(sessionId)) {
      sessions.set(sessionId, {
        messages: [],
        messagesById: new Map(),
        partsByMessageId: new Map(),
        tokenSnapshotsByMessageId: new Map(),
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

  function getMessageEntry(state, messageId, role) {
    let entry = state.messagesById.get(messageId)
    if (!entry) {
      entry = {
        id: messageId,
        role: role ?? "assistant",
        content: "",
        timestamp: new Date().toISOString(),
      }
      state.messagesById.set(messageId, entry)
      state.messages.push(entry)
    } else if (role) {
      entry.role = role
    }

    return entry
  }

  function getPartText(part) {
    if (!part || typeof part !== "object") return ""
    if (typeof part.text === "string") return part.text
    if (typeof part.prompt === "string") return part.prompt
    if (typeof part.description === "string") return part.description
    return ""
  }

  function rebuildMessageContent(state, messageId) {
    const parts = state.partsByMessageId.get(messageId)
    if (!parts || parts.size === 0) return ""

    return Array.from(parts.values())
      .filter(Boolean)
      .join("\n")
      .trim()
  }

  function setPartText(state, messageId, partId, text) {
    if (!messageId || !partId || !text) return

    let parts = state.partsByMessageId.get(messageId)
    if (!parts) {
      parts = new Map()
      state.partsByMessageId.set(messageId, parts)
    }

    parts.set(partId, text)
  }

  function removePartText(state, messageId, partId) {
    const parts = state.partsByMessageId.get(messageId)
    if (!parts) return
    parts.delete(partId)
  }

  function updateTokenTotals(state, messageId, tokens) {
    const current = {
      input: tokens?.input ?? 0,
      output: tokens?.output ?? 0,
      cacheRead: tokens?.cache?.read ?? 0,
    }
    const previous = state.tokenSnapshotsByMessageId.get(messageId) ?? {
      input: 0,
      output: 0,
      cacheRead: 0,
    }

    state.inputTokens += Math.max(0, current.input - previous.input)
    state.outputTokens += Math.max(0, current.output - previous.output)
    state.cacheTokens += Math.max(0, current.cacheRead - previous.cacheRead)
    state.tokenSnapshotsByMessageId.set(messageId, current)
  }

  function cwdToProjectName(cwd) {
    return (cwd ?? "").replace(/\//g, "-").replace(/^-/, "")
  }

  function updateProjectState(state, info) {
    if (!state.projectPath) {
      state.projectPath =
        info?.path?.root ?? info?.path?.cwd ?? info?.directory ?? ""
    }

    if (!state.projectName) {
      const cwd = info?.path?.cwd ?? info?.directory ?? directory ?? ""
      state.projectName = cwdToProjectName(cwd)
    }
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (!API_KEY) return
      const toolName = (input.tool ?? "").toLowerCase()
      const toolArgs = output.args ?? input.args ?? {}
      const sessionId = input.sessionId ?? input.session_id ?? input.sessionID ?? ""
      const { category, meta } = categorizeTool(toolName, toolArgs)

      void log(`tool.execute.before tool=${toolName}`)

      postAudit("/api/ingest/tool", {
        session_id: sessionId,
        developer_id: DEVELOPER_ID,
        event_type: "tool_use",
        phase: "pre",
        tool_name: toolName,
        tool_category: category,
        tool_input: toolArgs,
        tool_output: null,
        cwd: directory ?? "",
        ...meta,
      })
    },

    "tool.execute.after": async (input, output) => {
      if (!API_KEY) return
      const toolName = (input.tool ?? "").toLowerCase()
      const toolArgs = input.args ?? {}
      const sessionId = input.sessionId ?? input.session_id ?? input.sessionID ?? ""
      const toolResultRaw = output?.result ?? input?.result ?? null
      const toolOutput =
        toolResultRaw === null
          ? null
          : typeof toolResultRaw === "string"
            ? toolResultRaw
            : JSON.stringify(toolResultRaw)
      const { category, meta } = categorizeTool(toolName, toolArgs)

      void log(`tool.execute.after tool=${toolName}`)

      postAudit("/api/ingest/tool", {
        session_id: sessionId,
        developer_id: DEVELOPER_ID,
        event_type: "tool_use",
        phase: "post",
        tool_name: toolName,
        tool_category: category,
        tool_input: toolArgs,
        tool_output: toolOutput,
        cwd: directory ?? "",
        ...meta,
      })
    },

    event: async ({ event }) => {
      const props = event.properties ?? event
      void log(`event received: ${event.type}`)

      if (event.type === "session.created") {
        const info = props.info ?? props
        const sessionId = info.id ?? info.sessionID ?? info.sessionId
        if (!sessionId) return

        updateProjectState(getSession(sessionId), info)

        const sessionCwd = info.path?.cwd ?? directory ?? ""
        postAudit("/api/ingest/session", {
          session_id: sessionId,
          developer_id: DEVELOPER_ID,
          event_type: "session_start",
          cwd: sessionCwd,
          project_path: info.path?.root ?? sessionCwd,
          project_name: cwdToProjectName(sessionCwd),
        })
        return
      }

      if (event.type === "session.updated") {
        const info = props.info ?? props
        const sessionId = info.id ?? info.sessionID ?? info.sessionId
        if (!sessionId) return

        updateProjectState(getSession(sessionId), info)
        return
      }

      if (event.type === "message.updated") {
        const info = props.info ?? props.message ?? props
        const sessionId = info.sessionID ?? info.session_id ?? info.sessionId
        const messageId = info.id ?? info.messageID ?? info.messageId

        if (!sessionId || !messageId) {
          void log("message.updated ignored: missing session or message id")
          return
        }

        const state = getSession(sessionId)
        updateProjectState(state, info)

        const role = info.role ?? info.Role
        const entry = getMessageEntry(state, messageId, role)
        entry.timestamp = info.time?.created
          ? new Date(info.time.created).toISOString()
          : entry.timestamp

        if (role === "assistant") {
          updateTokenTotals(state, messageId, info.tokens)
          if (info.modelID) state.model = info.modelID
          if (info.providerID && !state.model) state.model = info.providerID
        }

        const content =
          typeof info.summary?.body === "string" && info.summary.body.trim()
            ? info.summary.body.trim()
            : rebuildMessageContent(state, messageId)

        if (content) entry.content = content

        void log(
          `message.updated stored for session ${sessionId} message=${messageId} role=${role ?? "unknown"} content_length=${entry.content.length}`,
        )
        return
      }

      if (event.type === "message.part.updated") {
        const part = props.part ?? props
        const sessionId = part.sessionID ?? props.sessionID ?? props.sessionId
        const messageId = part.messageID ?? props.messageID ?? props.messageId
        const partId = part.id ?? props.partID ?? props.partId

        if (!sessionId || !messageId || !partId) {
          void log("message.part.updated ignored: missing identifiers")
          return
        }

        const state = getSession(sessionId)
        const text = getPartText(part)
        if (!text) return

        setPartText(state, messageId, partId, text)

        const entry = state.messagesById.get(messageId)
        if (entry) {
          const content = rebuildMessageContent(state, messageId)
          if (content) entry.content = content
        }
        return
      }

      if (event.type === "message.part.removed") {
        const sessionId = props.sessionID ?? props.session_id ?? props.sessionId
        const messageId = props.messageID ?? props.messageId
        const partId = props.partID ?? props.partId

        if (!sessionId || !messageId || !partId) return

        const state = sessions.get(sessionId)
        if (!state) return

        removePartText(state, messageId, partId)

        const entry = state.messagesById.get(messageId)
        if (entry) {
          entry.content = rebuildMessageContent(state, messageId)
        }
        return
      }

      if (event.type === "session.idle") {
        const sessionId =
          props.sessionID ?? props.session_id ?? props.sessionId
        if (!sessionId) {
          void log("session.idle ignored: missing session id")
          return
        }
        if (!API_KEY) {
          void log(`session.idle ignored: missing API key for session ${sessionId}`)
          return
        }

        const state = sessions.get(sessionId)
        if (!state || state.messages.length === 0) {
          void log(`session.idle ignored: no accumulated state for session ${sessionId}`)
          return
        }

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

        postAudit("/api/ingest", payload)

        sessions.delete(sessionId)
      }
    },
  }
}
