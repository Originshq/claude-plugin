# OpenCode Audit Plugin Logging Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an append-only local log file beside the OpenCode audit plugin so we can confirm whether the plugin loads and which events it receives.

**Architecture:** Keep the audit payload and POST logic unchanged. Add a small file-logging helper inside the plugin module that appends timestamped lines to a sibling `opencode-audit.log` file, and call it from plugin startup and the event handler when important states occur. Use the log as a low-friction debugging aid rather than introducing any new dependency or external logging service.

**Tech Stack:** JavaScript ES modules, Node/Bun file system APIs, OpenCode plugin hooks.

---

### Task 1: Add append-only file logging helper

**Files:**
- Modify: `plugins/opencode-audit/index.js`

- [ ] **Step 1: Add a failing sanity check mentally**

Confirm the file currently has no local logging helper and no filesystem writes.

- [ ] **Step 2: Implement a small append helper**

Add logic to resolve a sibling `opencode-audit.log` path and append timestamped lines safely.

- [ ] **Step 3: Add startup and event markers**

Log when the plugin initializes, when an event arrives, and when the plugin ignores or processes a session.

- [ ] **Step 4: Keep the audit path unchanged**

Do not alter payload shape or POST behavior while adding logging.

### Task 2: Verify the plugin still loads

**Files:**
- Modify: `plugins/opencode-audit/index.js`

- [ ] **Step 1: Check syntax**

Run: `node --check plugins/opencode-audit/index.js`
Expected: no output, exit code 0.

- [ ] **Step 2: Confirm log file behavior**

Run OpenCode in a way that loads the plugin, then verify `plugins/opencode-audit.log` is created and receives lines.

- [ ] **Step 3: Commit the change**

Run: `git add plugins/opencode-audit/index.js docs/superpowers/plans/2026-04-09-opencode-audit-log.md && git commit -m "feat: add local audit plugin logging"`
