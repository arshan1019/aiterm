# TODO

Open work, with enough context to pick each item up later. Details live in the linked docs.

## Next up

- [ ] **UI bug pass.** You're testing on the phone and will report the bugs one at a time.

## Performance

Goal: top-tier performance, at least 60 fps (8 ms frames on 120 Hz phones), and efficient with memory, storage and CPU. The research, the audit evidence and the plan are in [docs/PERFORMANCE.md](docs/PERFORMANCE.md) (researched 15 October 2026; nothing implemented yet). Do them in this order:

- [ ] **P1. Ship release (AOT) builds instead of debug.** `build.yml` builds `--debug`. The 48 MB APK is mostly debug machinery: a 17 MB JIT kernel, a 15.7 MB debug engine, a 4.6 MB Vulkan validation layer and a 4.4 MB snapshot. Release keeps the same signing key (`buildTypes.release` already uses it). It needs R8 keep rules for our Kotlin and JNI classes, and an on-device check of the terminal, Linux install, agents, phone files, editor and SSH. Measure the APK before and after.
- [ ] **P2. Blocks: compute each file diff once.** `_ToolBlock.build` in `lib/agents/blocks/blocks_view.dart` runs `lineDiff` (longest-common-subsequence) for every visible edit on every rebuild, up to once a frame while replies stream. Keep the result with the `ToolDiff`, and move huge diffs to an isolate.
- [ ] **P3. Build app tabs lazily.** `lib/app/home_shell.dart` builds Projects, Terminal, Files and Settings at launch, because `IndexedStack` builds every child. Build each on first visit, as the workspace's `_built` already does and Wonderous's lazy IndexedStack does.
- [ ] **P4. Narrow the workspace rebuilds.** `lib/projects/project_screen.dart` rebuilds the whole workspace on any change to projects, navigation, tabs (every session's activity flip), agents, preview, chats or the repo. Give each badge and the app bar its own listener.
- [ ] **P5. Start only what the first frame needs.** `AppServices` (`lib/app/services.dart`) starts keep-alive, SSH keys, phone grants, port polling and agent-session loading during startup. Defer them until after the first frame.
- [x] **P6. Lower terminal scrollback** from 10,000 to 5,000 lines (`lib/terminal/terminal_session.dart`), or make it a setting. A full tab is about 10 MB; Termux keeps 2,000 lines by default.
- [ ] **P7. Poll ports less when idle.** `lib/preview/preview_controller.dart` probes ports every 3 s while visible. Back off to around 10 s when nothing has been seen or hinted.
- [ ] **P8. Cheaper tab transitions.** `lib/shared/fade_indexed_stack.dart` fades with `Opacity`, an offscreen layer over the whole screen for 220 ms. Use `FadeTransition` or no fade for top-level tabs.
- [ ] **P9. A "Show frame timings" switch** in Settings → About, which turns on the performance overlay in release builds so you can verify 60 or 120 fps on the phone. Optionally, a manual CI workflow that builds a profile APK for DevTools.

**Verify:** APK size; cold start (`adb shell am start -W`); the overlay's UI and raster graphs under 8 ms while scrolling a terminal, streaming a blocks reply with diffs open, switching tabs, and opening the editor; memory (`dumpsys meminfo`) with three tabs and a chat open.

## Agents and blocks

ACP features (blocks) have their own list with context: [docs/ACP-TODO.md](docs/ACP-TODO.md). It covers live checks with Claude, Codex and Gemini, a context meter, steering, deleting from History, compaction, subagents, forking, sign-in, URL forms, voice, agent commands in aiterm terminals, edits through the editor, and phone tools over MCP.

- [ ] **Blocks for plain shell commands,** using OSC 133 command marks. Not started; you asked for agent blocks first.

## Product

- [ ] **Git: history view and merge conflicts.** The current scope is the core loop (status, diff, stage, commit, push and pull, branches, clone, identity).
- [ ] **Docker:** researched only, nothing built.
- [ ] **M3 Expressive components** (button groups, split button, loading indicator) once Flutter's `material_ui` ships them.
- [ ] **Needle command model:** the fine-tune scored no better than the base model (dev 47% vs 47%, holdout 27% vs 32%) and wasn't shipped. The identical dev score suggests `needle build --lora` may not apply the LoRA; investigate before another run.

## Done recently

See [docs/PROJECT.md](docs/PROJECT.md) for everything built so far, and [docs/DESIGN.md, What we learned and applied](docs/DESIGN.md#what-we-learned-and-applied) for the research behind it.
