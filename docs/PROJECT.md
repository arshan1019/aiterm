# aiterm: what's been built

aiterm runs AI coding agents (Claude Code, Gemini CLI, Codex CLI) natively on an Android phone, on real projects. Underneath is Alpine Linux under proot, so `git`, `gh`, `node` and the agents behave as they do on a Linux machine. On top are project workspaces, git and GitHub, a terminal, a file manager, a code editor and a live preview.

This document records what exists, how it fits together, and why it was built that way. Two companion docs go deeper:

- [Design language](DESIGN.md): the visual rules and the research behind them.
- [User flow](USERFLOW.md): how people move through the app, and the back-stack rules.

## Where things stand (15 October 2026)

- **Builds:** every APK comes from GitHub Actions and is published to the rolling `debug-latest` release. All builds are signed with one key, so each installs over the last.
- **Tests:** about 290 tests pass on CI, including widget tests, WCAG contrast checks and layout checks at 200% text.
- **Backup of the pre-redesign look:** tag `design-v1`, branch `design-v1-backup` and the `design-v1` release with its APK.
- **In progress:** a UI bug pass, driven by on-device testing.

## What's built

### Linux underneath

- **Alpine under proot.** proot is built from Termux's source in CI, with a fix that serves `/proc/self/uid_map`; Claude Code's cross-session messaging needs it. proot runs with proot-distro's flags and fake `/proc` entries, so programs see a normal Linux.
- **A real terminal.** A JNI pseudo-terminal, Termux-grade key handling, and output batched over one channel.
- **What agents expect.** A standard userland: procps, GNU coreutils, findutils, grep, sed, diffutils, less and ssh. Each agent's own packages install alongside it.
- **Sessions survive the app.** A foreground service keeps shells running, and the app reattaches to them after being swiped away. A notification arrives when a command finishes or a program needs input.
- **Keep-alive checklist.** Battery optimisation, notifications, and Android's child-process limit, which is fixed through Wireless debugging.
- **Backup and restore** of the whole Linux setup.
- **Android's shell** is available as a fallback when Linux isn't installed (first-run Skip).

### Terminal

- **Tabs:** pinning, renaming, and scoping per project (each project keeps its own sessions).
- **Status dots per tab:** working, needs input, idle or ended.
- **Shell integration:** the app knows the current folder and when each command ends. Launch commands rerun in a fresh shell. A killed session (exit 137) is detected and explained.
- **Touch:** tapping a URL selects it with a Copy/Open toolbar; selection handles have a magnifier; an extra-keys row (Esc, Tab, Ctrl, Alt, arrows) has screen-reader names.
- **Keyboard:** it stays shut on tab switches, and content no longer jumps around it.
- **Assistant:** an on-device model (Needle) turns "what do you want to do?" into commands. Failed commands get one-tap fixes.
- **Colours:** the terminal palette comes from the app's colour system. It can stay dark in the light theme, or use pure black.

### AI agents

- **One-tap installs** for Claude Code, Gemini CLI and Codex CLI. Each install covers the agent's dependencies and the vendor's own install command. Missing dependencies are repaired on open.
- **Opening an agent "in" a folder** makes that folder a project. Reopening goes back to the agent's existing tab.

### Blocks (optional; agents keep their own UI by default)

Settings → Agent settings → **Blocks** shows an agent's work as native blocks instead of its terminal UI.

- **Protocol:** blocks use the [Agent Client Protocol](https://agentclientprotocol.com) (ACP), the standard Zed and JetBrains use.
  - Gemini CLI speaks it natively (`gemini --acp`).
  - Claude Code and Codex use the official adapters (`@agentclientprotocol/claude-agent-acp`, `codex-acp`). They install on first use with `--omit=optional` and run the agents already installed (`CLAUDE_CODE_EXECUTABLE`, `CODEX_PATH`), so there's one copy of each agent and one sign-in.
- **What renders:**
  - Your messages, and the agent's replies as Markdown, with code in mono.
  - Tool calls: status, kind icon, the command or path in mono, +/− counts, and diffs or output when tapped.
  - The plan with progress. Thinking, when turned on.
- **Permission requests** stay pinned above the message box in one fixed layout: what the agent wants to do (the command, the edit's diff, the plan), then its choices as full-width buttons, one per row, in the agent's own order. The agent's preferred choice is filled and declines are in red. Some of Claude's safety checks deliberately lead with No.
- **Questions:** Claude's AskUserQuestion arrives as an ACP form (aiterm advertises `elicitation.form`). Its options are tappable rows, with an optional "Other" box and Skip; a single pick-one question answers on tap.
- **Several chats per agent in a project** ("Claude Code", "Claude Code 2", …), from + → New Claude Code chat. They share one adapter process (ACP multiplexes sessions), so another chat costs a session, not another Node process. The first chat resumes the remembered session; the others start fresh.
- **History** (the clock icon, top right of the chat bar) lists the project's past chats by title, newest first, grouped by date as in Chrome (Today, Yesterday, Previous 7 days, then months), with search once the list is long. Tapping one opens it as blocks in that agent, replaying it with `session/load`, or goes to it if it's already open. The list comes from the agent's `session/list`; listing alone doesn't leave the agent running.
- **The agent's mode** sits in the chat bar and its model in the menu. The last choice of each is remembered per agent.
- **Message box:**
  - Attachments, growing text, and Attach and Send inside one rounded container. Attach, the text's first line and Send share one 48 dp line; as the text grows, both buttons stay with the last line.
  - Typing "/" lists the agent's commands.
  - Messages typed while the agent starts go out once it's ready.
- **Attachments:** files are copied to `~/.cache/aiterm/attachments`, which is granted to the session. Images go inline (scaled below the API cap); other files go as links.
- **A thinking orb** shows while the agent works. Its motion and label follow the activity: Thinking, Reading, Editing, Running or Writing.
- **New chat** reuses the running adapter, so it's near-instant. Sessions resume after a restart where the agent supports it.
- **Scrolling stays smooth while replies stream:** replies are parsed once, the rows you're reading hold still, and an arrow returns you to the latest.
- **Terminal alongside:** when a project has both blocks and terminals, the Agent tab switches between them, and both keep running.
- **Verification:** the client was tested live against the real Claude adapter. Codex and Gemini follow the same protocol but haven't been tested live yet.

### Projects and the workspace

- **Projects** is the home tab. Each card shows the project's branch, changes, sync state and agent activity.
- **Add project** offers four choices: New project (from a template), Clone repository, Import from phone, Open Linux folder. A GitHub button picks one of your repositories.
- **The workspace** is a page with its own tabs: Agent, Changes, Files and Preview.
  - Badges show changes, an agent waiting for you, and a live server.
  - Back steps through the current tab's history, then to Agent, then out.
- **Card menu:** Open, Rename, Export to phone (hidden for projects already on the phone), Remove (with Undo), Delete (asks first).

### Git and GitHub

- **Real tools:** `git` and `gh` run in Linux. Status is parsed from porcelain output, and operations run one at a time, never overlapping.
- **Changes tab:**
  - Stage and unstage, line diffs, commit and push, branches, fetch and pull.
  - A suggested commit message, results shown inline, and the commit identity asked for once.
- **GitHub sign-in** uses `gh auth login --web` on plain pipes (not a terminal), so gh prints the code and URL with no prompts. It uses GitHub's official mark.
- **SSH keys** live in Android's keystore with an ssh-agent, and can be added to GitHub in one tap.

### Files and the phone

- **Two places:** Linux storage, and phone storage you choose: picked folders, or all files.
- **Moving files between them:** copy, move and paste across both. Files can be imported into a project from the phone or exported to it.
- **Share to aiterm** from any app files the shared items into a project.

### Editor and preview

- **The editor** is CodeMirror 6 in a WebView, with language servers running in Linux (one-tap installs) for highlighting and linting. This is Acode's approach; VS Code parts were ruled out.
- **The preview** shows dev servers running in Linux (`localhost` ports), announced as they start.

### First run

- **One full-screen setup** with Skip. You pick agents while Linux is already downloading; then Linux, git tools and the agents install in one go.
- **Meanwhile,** keep-alive and GitHub sign-in are offered under the progress.

### Settings

| Group | Contents |
|---|---|
| Appearance | Theme (System, Light, Dark); Wallpaper colors (Android 12+); High contrast; Compact lists; Haptic feedback |
| Terminal | Text size, Always dark, Black background |
| Environment | Linux status |
| Agent settings | AI agents page, Blocks, Blocks per agent, Show thinking |
| GitHub | Sign in or out, commit name and email |
| Keep sessions alive | The keep-alive checklist |
| SSH keys | Create, copy, add to GitHub, delete |
| Backup | Back up and restore |

### Design and accessibility

The rules and their evidence are in [DESIGN.md](DESIGN.md). Its section [What we learned and applied](DESIGN.md#what-we-learned-and-applied) pairs each research finding (platform guidelines, studies, admired apps, your on-device tests) with what it changed. The flow and onboarding rules are in [USERFLOW.md §7](USERFLOW.md#7-design-principles-we-follow). In short:

- **Type:** two voices. IBM Plex Sans for the app; JetBrains Mono only for literal text (paths, branches, commands, code).
- **Structure:** tone, not borders, separates groups. Sentence case everywhere.
- **Icons:** Material Symbols Outlined, subset to the app's icons by `tool/icons/generate.py`. Fill marks state. No sparkles for AI.
- **Colour:** an OKLCH palette tinted toward a teal accent, with the accent rationed to a few jobs. High contrast meets AAA. Wallpaper accents keep their contrast at every hue.
- **Touch and motion:**
  - 48 dp touch targets.
  - Haptics from Android's own constants, used sparingly and only for things on screen; a switch turns them off.
  - Animations stop when the system's "Remove animations" setting is on.
- **Errors** show inline, next to their cause. Snackbars are only for success and Undo.
- **Checks:** WCAG contrast tests for every theme; the accessibility guidelines (tap targets, labels, contrast) run in widget tests; main screens are laid out at 200% text on a phone-sized screen.

## How the code is organised

Each folder under `lib/` is one feature; the map is at the top of `lib/main.dart`.

| Folder | What's in it |
|---|---|
| `app/` | Startup, `AppServices` (every shared service, handed down through `AppScope`), navigation and back rules, theme tokens (`AppColors`, `TerminalPalette`, `Motion`, `Radii`), the generated `AppIcons` |
| `linux/` | Alpine under proot: install, process specs, shell profile |
| `terminal/` | Sessions and tabs (models), deck, panes, tab strip, extra keys |
| `agents/` | Catalog and installer; `acp/` (ACP client, chat model, registry, attachments); `blocks/` (the blocks UI) |
| `projects/` | Store, service (create, clone, import), Projects screen, workspace |
| `git/` | Runner, parsers, repo model, Changes and diff screens, GitHub auth, repository picker |
| `files/`, `phone/` | File browser and clipboard; phone storage through Android's document picker (SAF), Share target |
| `editor/` | CodeMirror bridge, language-server processes and framing |
| `onboarding/`, `keep_alive/`, `backup/`, `ssh/`, `preview/`, `assistant/`, `settings/` | As named |
| `platform/` | Method channels to Android: pty, haptics, system colors, environment |
| `shared/` | Sheet frame, dialogs and forms, groups, Markdown, line diff, bottom tabs |

On the Android side, `MainActivity.kt` registers the channels: pty, phone files, haptics, colours, keep-alive, backup and SSH. `editor/` holds the CodeMirror bundle source, built into `assets/editor/`.

## Builds, releases and tests

- **CI only.** The phone is too weak to build. All workflows are manual:
  - `test.yml`: unit and widget tests, plus Kotlin tests.
  - `build.yml`: the arm64 debug APK, signed with the shared key from a repository secret, signature checked, published to `debug-latest`. It installs the Android NDK up front with retries, after a corrupted download once failed a build.
  - `screenshots.yml`: renders about 38 screens, in both themes and in edge states, for layout review.
  - `finetune.yml`: the Needle model fine-tuning chain.
- **Locally:** `flutter analyze` and the unit tests run in this sandbox; widget tests overflow its stack, so they run on CI.
- **Signing:** every APK's signing certificate has SHA-256 `59f76149…bf9ef`. The keystore is kept out of the repository.

## Decisions and why

| Decision | Why |
|---|---|
| Projects as the home, agents inside projects | The job is agents working on real code; tools serve that |
| Real Linux tools, not reimplementations | "Linux must act like Linux": fix root causes, follow Termux |
| Agents' own terminal UI by default; blocks optional | Their UIs are good; blocks are an alternative, not a replacement |
| ACP for blocks, not terminal scraping | The standard editors use; structured, with permissions and diffs |
| CodeMirror + language servers, no VS Code parts | Light enough for a phone; your decision (14 October) |
| Project folders live in Linux storage | git and executables break on the phone's FUSE storage; phone files move in and out by import and export |
| Phone access: chosen folders or all files, as equals | Your call: all-files access must not be hidden in Advanced |
| Self-explanatory buttons, no explanatory captions | Your rule: the interface explains itself |
| No hidden long-press-only gestures | Every action is a visible tap away; long-press is only a shortcut |
| Icon font subset in the repo | Debug builds don't tree-shake icons; the full fonts would add about 30 MB |
| Batched changes, one CI build per batch | Your workflow |
| Commits use the GitHub noreply address and carry no co-author line | Your instructions |

## Not done yet

Tracked with context in [TODO.md](../TODO.md); the performance plan is in [PERFORMANCE.md](PERFORMANCE.md).

- **Blocks for plain shell commands** (OSC 133 command marks).
- **ACP with Codex and Gemini,** tested live on a device.
- **M3 Expressive components,** once Flutter ships them.
- **Git:** history view and merge conflicts.
- **Docker:** researched only; nothing built.
- **The Needle fine-tune** wasn't shipped: the tuned model scored no better than the base model.
- **The UI bug pass** from your on-device testing.

## Timeline

- **13 October:** the base.
  - A terminal and file manager, then a real pseudo-terminal with Alpine under proot.
  - Tabs, shell integration, keep-alive, notifications, SSH keys, backup.
  - One-tap agents, then the pivot to projects with git and GitHub.
- **14 October:** flow, polish and agents.
  - The user-flow plan and its friction fixes: one-screen setup, agent tabs owned by projects, inline git results.
  - Workspace navigation and back rules. Phone storage and Share to aiterm. The code editor.
  - The four-verb Add project, accessibility, GitHub sign-in that works, one bottom-sheet frame.
  - Design research, then three design batches: type, palette, icons, appearance options and 200% text checks.
  - High contrast, Agent settings, and blocks over ACP, refined with New chat, attachments, the thinking orb, the composer, haptics and smooth scrolling.
- **15 October:** this document.
