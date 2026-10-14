# ACP features: TODO

Everything still to build or check on top of the Agent Client Protocol (ACP), which powers blocks. Each item says what it gives you, which protocol pieces it uses, whether Claude's adapter supports it, and roughly how big it is. Claude Code comes first; Codex and Gemini get tuned later.

## Background

- **How blocks talk to agents:** blocks speak ACP: JSON-RPC over newline-delimited stdio ([agentclientprotocol.com](https://agentclientprotocol.com); schema v1.25.0, October 2026).
  - Claude Code and Codex use the official adapters (`@agentclientprotocol/claude-agent-acp` 0.90, `@agentclientprotocol/codex-acp` 2.2). Gemini runs natively (`gemini --acp`).
  - One adapter process per agent per project hosts every chat with it (`lib/agents/acp/acp_host.dart`).
- **The code:** the client is in `lib/agents/acp/`: `acp_connection.dart` (JSON-RPC), `acp_host.dart` (process and session routing), `agent_chat.dart` (one session as blocks), `agent_chats.dart` (registry, history). The UI is in `lib/agents/blocks/`.
- **What the client advertises:** `fs` and `terminal` are off, so agents use their own tools; `elicitation.form` is on, for questions.
- **Already in use:** plans, tool calls, diffs, thinking, slash commands, modes, models, permissions, questions (form elicitation), `session/new`/`load`/`list`/`close`, several sessions per process, images and files in prompts, cancel.
- **How Claude's adapter behaves:** see its source (`dist/acp-agent.js`, `dist/permissions/`).
  - Option order carries Claude's default: some safety checks lead with No.
  - AskUserQuestion needs `elicitation.form`.
  - The adapter can reuse the installed Claude Code via `CLAUDE_CODE_EXECUTABLE`.

## Check on a phone

- [ ] **Try questions, plan approvals, several chats and History live with Claude.** They're covered by tests against a scripted agent built from the adapter's source; real Claude hasn't run them yet. Watch for: question forms with several questions, plan approval options and their long labels, a second chat sharing the process, History titles from `session/list`, and `session/load` replaying a past chat.
- [ ] **Test Codex and Gemini over ACP.** Claude was tested live (handshake, modes, models, one turn). Codex (`codex-acp`, installed with `--omit=optional` and `CODEX_PATH`) and Gemini (`gemini --acp`) haven't run yet. Check sign-in (both may answer `authRequired`), their modes (Gemini uses `session/set_mode`, not config options), whether each supports `session/list`, and how their tool calls render.

## Small

- [ ] **Context meter.**
  - What it gives you: how full Claude's context is, for example "62% used", in the chat bar or under the message box, plus cost if wanted.
  - Protocol: the `usage_update` session update (`used`, `size`, optional `cost`). Claude sends it after every step; today the client ignores it (`agent_chat.dart`, `_onNotification`, default branch).
  - Design: muted, tabular figures; warning colour past about 85%. No new setting.
- [ ] **Steering: send while Claude works.**
  - What it gives you: type a correction or addition mid-turn, as in Claude Code's own UI, instead of waiting or stopping.
  - Protocol: Claude's adapter advertises `_meta.steering.supported` and `_meta.claudeCode.promptQueueing` in its initialize reply.
  - Work: check the adapter source for how a queued prompt is sent (another `session/prompt` during a turn), then let the message box send while busy, with Stop beside Send. Today `send` refuses while busy (`AgentChat.send`).
- [ ] **Delete chats from History.**
  - What it gives you: remove old conversations.
  - Protocol: `session/delete`. Claude advertises `sessionCapabilities.delete`.
  - Design: no hidden swipe; a visible ⋮ on each row (Delete, with Undo), and close any open chat on that session first.
- [ ] **Compaction status.**
  - What it gives you: "Compacting…" instead of an unexplained pause when Claude summarises a long chat, then a small block with the summary.
  - Protocol: the `compaction_update` (`in_progress`, `completed`, `failed`, `cancelled`) and `compaction_summary_chunk` session updates.
- [ ] **Subagent transcripts.**
  - What it gives you: Claude's sub-tasks (its Agent/Task tool) as nested, collapsible blocks inside the parent tool block, instead of one opaque tool call.
  - Protocol: the adapter lists "nested subagent transcripts"; check how it reports them (child sessions or `parentToolUseId` in `_meta`).

## Medium

- [ ] **Fork a chat.**
  - What it gives you: branch a conversation to try another approach, keeping the original.
  - Protocol: Claude advertises `sessionCapabilities.fork`; find the method and parameters in the adapter (not in the stable v1 schema we checked).
  - Design: on a user block's long-press menu and its visible ⋮, "Fork from here", which opens the fork as a new chat ("Claude Code 2").
- [ ] **Sign in without leaving blocks.**
  - What it gives you: Claude's (or Codex's) sign-in inside the chat, not in the agent's terminal UI as today ("Sign in" opens the terminal).
  - Protocol: `authMethods` in the initialize reply, then `authenticate`; the `terminal` auth type (client capability `auth.terminal`); `logout`.
  - Design: a sign-in block with the code and URL, like the GitHub sign-in sheet.
- [ ] **URL forms (elicitation `url` mode).**
  - What it gives you: MCP servers that need OAuth (and other browser steps) open the browser and come back.
  - Protocol: client capability `elicitation.url`, `elicitation/create` with `mode: url`, and the `elicitation/complete` notification. Claude bridges MCP OAuth to it.
- [ ] **Voice messages.**
  - What it gives you: speak a prompt.
  - Protocol: `audio` content blocks in `session/prompt`, only where the agent advertises `promptCapabilities.audio` (Claude advertised image and embedded context, not audio, in our test). Otherwise transcribe on the device and send text.

## Large (what would make aiterm unique)

- [ ] **Agent commands in aiterm's own terminals.**
  - What it gives you: Claude's shell commands run in aiterm terminal tabs, with live output streaming inside the tool block and a tap to open the real terminal. Commands keep running if the chat is closed.
  - Protocol: client capability `terminal: true`, and `terminal/create`, `output`, `wait_for_exit`, `kill`, `release`. Tool calls then carry `{type: terminal, terminalId}` content (today ignored in `AgentChat._tool`).
  - Work: map onto `TerminalTabs` and the PTY; sessions scoped to the project; output capped.
- [ ] **Edits through aiterm's editor.**
  - What it gives you: Claude reads and writes files through aiterm, so files open in the editor (with unsaved changes) are respected, and every write can be reviewed or undone.
  - Protocol: client capabilities `fs.readTextFile` and `fs.writeTextFile`; `fs/read_text_file` and `fs/write_text_file`.
  - Work: serve them from Linux storage (`linux.hostPath`) and the editor's open buffers.
- [ ] **Phone tools for agents (MCP).**
  - What it gives you: aiterm hands Claude tools only a phone app can give: phone files (the document picker), clipboard, notifications ("tell me when done"), camera or photo, share sheet, GitHub (via `gh`), the project's live preview port.
  - Protocol: `mcpServers` in `session/new` and `session/load` (today `[]`). Claude advertises `mcpCapabilities.http` and `sse`, so aiterm can serve an HTTP MCP endpoint on localhost.
  - Work: an MCP server inside the app; each tool behind a permission (ACP's own request flow).

## Related, outside ACP

- [ ] **Blocks for plain shell commands** (OSC 133 command marks) for the Terminal tab. Not started; agent blocks came first. Tracked in [TODO.md](../TODO.md).
