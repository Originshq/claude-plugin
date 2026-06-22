# Plugins

Write your own plugins to extend OpenCode.

Plugins allow you to extend OpenCode by hooking into various events and customizing behavior. You can create plugins to add new features, integrate with external services, or modify OpenCode’s default behavior.

For examples, check out the [plugins](https://opencode.ai/docs/ecosystem#plugins) created by the community.

---

## [Use a plugin](https://opencode.ai/#use-a-plugin)

There are two ways to load plugins.

---

### [From local files](https://opencode.ai/#from-local-files)

Place JavaScript or TypeScript files in the plugin directory.

- `.opencode/plugins/` - Project-level plugins
- `~/.config/opencode/plugins/` - Global plugins

Files in these directories are automatically loaded at startup.

---

### [From npm](https://opencode.ai/#from-npm)

Specify npm packages in your config file.

opencode.json

```
{  "$schema": "https://opencode.ai/config.json",  "plugin": ["opencode-helicone-session", "opencode-wakatime", "@my-org/custom-plugin"]}
```

Both regular and scoped npm packages are supported.

Browse available plugins in the [ecosystem](https://opencode.ai/docs/ecosystem#plugins).

---

### [How plugins are installed](https://opencode.ai/#how-plugins-are-installed)

**npm plugins** are installed automatically using Bun at startup. Packages and their dependencies are cached in `~/.cache/opencode/node_modules/`.

**Local plugins** are loaded directly from the plugin directory. To use external packages, you must create a `package.json` within your config directory (see [Dependencies](https://opencode.ai/#dependencies)), or publish the plugin to npm and [add it to your config](https://opencode.ai/docs/config#plugins).

---

### [Load order](https://opencode.ai/#load-order)

Plugins are loaded from all sources and all hooks run in sequence. The load order is:

1. Global config (`~/.config/opencode/opencode.json`)
2. Project config (`opencode.json`)
3. Global plugin directory (`~/.config/opencode/plugins/`)
4. Project plugin directory (`.opencode/plugins/`)

Duplicate npm packages with the same name and version are loaded once. However, a local plugin and an npm plugin with similar names are both loaded separately.

---

## [Create a plugin](https://opencode.ai/#create-a-plugin)

A plugin is a **JavaScript/TypeScript module** that exports one or more plugin functions. Each function receives a context object and returns a hooks object.

---

### [Dependencies](https://opencode.ai/#dependencies)

Local plugins and custom tools can use external npm packages. Add a `package.json` to your config directory with the dependencies you need.

.opencode/package.json

```
{  "dependencies": {    "shescape": "^2.1.0"  }}
```

OpenCode runs `bun install` at startup to install these. Your plugins and tools can then import them.

.opencode/plugins/my-plugin.ts

```
import { escape } from "shescape"
export const MyPlugin = async (ctx) => {  return {    "tool.execute.before": async (input, output) => {      if (input.tool === "bash") {        output.args.command = escape(output.args.command)      }    },  }}
```

---

### [Basic structure](https://opencode.ai/#basic-structure)

.opencode/plugins/example.js

```
export const MyPlugin = async ({ project, client, $, directory, worktree }) => {  console.log("Plugin initialized!")
  return {    // Hook implementations go here  }}
```

The plugin function receives:

- `project`: The current project information.
- `directory`: The current working directory.
- `worktree`: The git worktree path.
- `client`: An opencode SDK client for interacting with the AI.
- `$`: Bun’s [shell API](https://bun.com/docs/runtime/shell) for executing commands.

---

### [TypeScript support](https://opencode.ai/#typescript-support)

For TypeScript plugins, you can import types from the plugin package:

my-plugin.ts

```
import type { Plugin } from "@opencode-ai/plugin"
export const MyPlugin: Plugin = async ({ project, client, $, directory, worktree }) => {  return {    // Type-safe hook implementations  }}
```

---

### [Events](https://opencode.ai/#events)

Plugins can subscribe to events as seen below in the Examples section. Here is a list of the different events available.

#### [Command Events](https://opencode.ai/#command-events)

- `command.executed`

#### [File Events](https://opencode.ai/#file-events)

- `file.edited`
- `file.watcher.updated`

#### [Installation Events](https://opencode.ai/#installation-events)

- `installation.updated`

#### [LSP Events](https://opencode.ai/#lsp-events)

- `lsp.client.diagnostics`
- `lsp.updated`

#### [Message Events](https://opencode.ai/#message-events)

- `message.part.removed`
- `message.part.updated`
- `message.removed`
- `message.updated`

#### [Permission Events](https://opencode.ai/#permission-events)

- `permission.asked`
- `permission.replied`

#### [Server Events](https://opencode.ai/#server-events)

- `server.connected`

#### [Session Events](https://opencode.ai/#session-events)

- `session.created`
- `session.compacted`
- `session.deleted`
- `session.diff`
- `session.error`
- `session.idle`
- `session.status`
- `session.updated`

#### [Todo Events](https://opencode.ai/#todo-events)

- `todo.updated`

#### [Shell Events](https://opencode.ai/#shell-events)

- `shell.env`

#### [Tool Events](https://opencode.ai/#tool-events)

- `tool.execute.after`
- `tool.execute.before`

#### [TUI Events](https://opencode.ai/#tui-events)

- `tui.prompt.append`
- `tui.command.execute`
- `tui.toast.show`

---

## [Examples](https://opencode.ai/#examples)

Here are some examples of plugins you can use to extend opencode.

---

### [Send notifications](https://opencode.ai/#send-notifications)

Send notifications when certain events occur:

.opencode/plugins/notification.js

```
export const NotificationPlugin = async ({ project, client, $, directory, worktree }) => {  return {    event: async ({ event }) => {      // Send notification on session completion      if (event.type === "session.idle") {        await $`osascript -e 'display notification "Session completed!" with title "opencode"'`      }    },  }}
```

We are using `osascript` to run AppleScript on macOS. Here we are using it to send notifications.

---

### [.env protection](https://opencode.ai/#env-protection)

Prevent opencode from reading `.env` files:

.opencode/plugins/env-protection.js

```
export const EnvProtection = async ({ project, client, $, directory, worktree }) => {  return {    "tool.execute.before": async (input, output) => {      if (input.tool === "read" && output.args.filePath.includes(".env")) {        throw new Error("Do not read .env files")      }    },  }}
```

---

### [Inject environment variables](https://opencode.ai/#inject-environment-variables)

Inject environment variables into all shell execution (AI tools and user terminals):

.opencode/plugins/inject-env.js

```
export const InjectEnvPlugin = async () => {  return {    "shell.env": async (input, output) => {      output.env.MY_API_KEY = "secret"      output.env.PROJECT_ROOT = input.cwd    },  }}
```

---

### [Custom tools](https://opencode.ai/#custom-tools)

Plugins can also add custom tools to opencode:

.opencode/plugins/custom-tools.ts

```
import { type Plugin, tool } from "@opencode-ai/plugin"
export const CustomToolsPlugin: Plugin = async (ctx) => {  return {    tool: {      mytool: tool({        description: "This is a custom tool",        args: {          foo: tool.schema.string(),        },        async execute(args, context) {          const { directory, worktree } = context          return `Hello ${args.foo} from ${directory} (worktree: ${worktree})`        },      }),    },  }}
```

The `tool` helper creates a custom tool that opencode can call. It takes a Zod schema function and returns a tool definition with:

- `description`: What the tool does
- `args`: Zod schema for the tool’s arguments
- `execute`: Function that runs when the tool is called

Your custom tools will be available to opencode alongside built-in tools.

---

### [Logging](https://opencode.ai/#logging)

Use `client.app.log()` instead of `console.log` for structured logging:

.opencode/plugins/my-plugin.ts

```
export const MyPlugin = async ({ client }) => {  await client.app.log({    body: {      service: "my-plugin",      level: "info",      message: "Plugin initialized",      extra: { foo: "bar" },    },  })}
```

Levels: `debug`, `info`, `warn`, `error`. See [SDK documentation](https://opencode.ai/docs/sdk) for details.

---

### [Compaction hooks](https://opencode.ai/#compaction-hooks)

Customize the context included when a session is compacted:

.opencode/plugins/compaction.ts

```
import type { Plugin } from "@opencode-ai/plugin"
export const CompactionPlugin: Plugin = async (ctx) => {  return {    "experimental.session.compacting": async (input, output) => {      // Inject additional context into the compaction prompt      output.context.push(`## Custom Context
Include any state that should persist across compaction:- Current task status- Important decisions made- Files being actively worked on`)    },  }}
```

The `experimental.session.compacting` hook fires before the LLM generates a continuation summary. Use it to inject domain-specific context that the default compaction prompt would miss.

You can also replace the compaction prompt entirely by setting `output.prompt`:

.opencode/plugins/custom-compaction.ts

```
import type { Plugin } from "@opencode-ai/plugin"
export const CustomCompactionPlugin: Plugin = async (ctx) => {  return {    "experimental.session.compacting": async (input, output) => {      // Replace the entire compaction prompt      output.prompt = `You are generating a continuation prompt for a multi-agent swarm session.
Summarize:1. The current task and its status2. Which files are being modified and by whom3. Any blockers or dependencies between agents4. The next steps to complete the work
Format as a structured prompt that a new agent can use to resume work.`    },  }}
```

When `output.prompt` is set, it completely replaces the default compaction prompt. The `output.context` array is ignored in this case.