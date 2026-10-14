# Performance: research, audit and plan

The goal is for aiterm to perform like a top-tier app: at least 60 fps rendering (8 ms per frame on 120 Hz phones), and efficient with memory, storage and CPU. This file records what the research says, what the audit of our code found, and the plan. Each plan item is tracked in [TODO.md](../TODO.md). Researched and audited on 15 October 2026; nothing in this file has been implemented yet.

## What the research says

### Measure the right build

- **Debug numbers mean nothing.** Debug mode runs JIT-compiled Dart with assertions and debugging aids. Flutter calls its performance data "meaningless for optimization" ([Flutter's modes](https://flutter.googlesource.com/mirrors/flutter/+/HEAD/docs/engine/Flutter%27s-modes.md)).
- **Profile mode** compiles ahead of time to native code, like release, but keeps the tracing hooks and DevTools profilers. **Release** is for users: AOT code, tree shaking, no debugging aids.
- **Use a physical device.** Emulators don't reflect real GPU and CPU behaviour ([rendering performance](https://docs.flutter.dev/perf/rendering-performance)).
- **The workflow:** run `flutter run --profile` on a phone, turn on the performance overlay (top graph: raster thread, bottom graph: UI thread), find slow frames in DevTools, fix the work on the slow thread, then measure again.

### The frame budget

- About 16 ms per frame at 60 Hz. Flutter's guidance: aim for **8 ms or less to build and 8 ms or less to render**. That keeps 120 Hz phones smooth (8 ms frames), saves battery and heat, and holds up on low-end devices ([best practices](https://docs.flutter.dev/perf/best-practices)).

### The UI thread: build and layout

- Avoid repeated or costly work in `build()`; it can run on any ancestor's rebuild.
- Split large widgets by how they change, and call `setState` as low in the tree as possible.
- Reusing the same child instance stops the rebuild there: pass static subtrees through `child:` (`AnimatedBuilder`, `TransitionBuilder`).
- Prefer a `StatelessWidget` over a helper function.
- Build strings with `StringBuffer`, not `+` in loops.
- Use lazy builders (`ListView.builder`). Avoid intrinsic layout passes, which lay everything out twice; DevTools labels them "intrinsics".
- Move heavy parsing and computation to isolates ([isolates](https://docs.flutter.dev/perf/isolates)).

### The raster thread: painting and compositing

- `saveLayer` allocates an offscreen buffer and switches render targets, which is costly on mobile GPUs. These trigger it: `Opacity` (at values between 0 and 1), `ShaderMask`, `ColorFilter`, `Chip` with a disabled alpha, `Text` with an overflow shader, and `Clip.antiAliasWithSaveLayer`. Find them with `checkerboardOffscreenLayers`.
- **Opacity:** use a semi-transparent colour for simple shapes and text, the image's own `opacity`, or `FadeInImage`. In lists and animations, prefer `AnimatedOpacity` or `FadeTransition` over `Opacity`.
- **Clipping** without `saveLayer` still costs. Use `borderRadius` instead of clip rectangles, and avoid clipping during animations.
- **Shader jank:** Impeller, the default renderer on Android API 29+, compiles shaders ahead of time, which removes first-run animation stutter.

### What the Wonderous team did (gskinner)

Source: [Flutter: Rendering Optimization Tips](https://blog.gskinner.com/archives/2022/09/flutter-rendering-optimization-tips.html).

1. **No extra opacity layers.** Fade with colour opacity (`withOpacity` on `Container`, `ColoredBox` and text styles) and `Image.opacity`. They added a `FadeColorTransition` helper. Fading children instead of the parent can change compositing, so check the visuals.
2. **No oversized images.** Every network image goes through an `AppImage` widget with `cacheWidth`/`ResizeImage`, sized from `MediaQuery` size × devicePixelRatio × a scale factor. Debug with `debugInvertOversizedImages`.
3. **RepaintBoundary only where measured.** For example, around a timeline repainting under scrolled content. "Scattering them in a UI arbitrarily can actually reduce performance." Debug with `debugRepaintRainbowEnabled`.
4. **`ImageFiltered` instead of `BackdropFilter`** to blur your own content: about the same look, noticeably faster.
5. **A lazy IndexedStack.** Build tabs on first visit; `IndexedStack` builds every child at once, which stutters the first switch.

### Google's own apps

- **Google Classroom** benchmarked latency, jank, memory, binary size and accessibility. After moving to Flutter it reported 62% lower median startup latency and 63% lower latency on its tracked user journeys ([case study](https://flutter.dev/showcase/google-classroom)).
- **NotebookLM** shipped a 4.8-star Flutter app in seven months ([talk](https://www.youtube.com/watch?v=pMoUg3dkDJk)).
- The lesson: set budgets for startup, jank, memory and size, and measure them.

### Research papers

No peer-reviewed empirical study of Flutter performance turned up; there are theses and surveys.

- A UvA master's thesis comparing Flutter with native found larger binaries and higher resource use in hardware-intensive tasks, with weaker memory management on Android ([thesis](https://staff.fnwi.uva.nl/a.s.z.belloum/MSctheses/MScthesis_Fangqi_lin.pdf)).
- A literature review credits Flutter's strong performance to its rendering engine, while noting app size and memory as weak spots ([Oulu](https://oulurepo.oulu.fi/handle/10024/54358)).

Both point at the same levers for us: binary size, memory, and work on the main thread.

### Memory and size

- Images are the biggest memory lever: decode at display size (`cacheWidth`/`cacheHeight`, `ResizeImage`) ([example](https://saropa-contacts.medium.com/how-we-reduced-flutter-memory-usage-by-375mb-image-optimization-strategies-5a097246ee0c)).
- `flutter build apk --analyze-size` shows what's in the binary.
- Release builds tree-shake code and icon fonts.

## What the audit found (with evidence)

Already in good shape:

- **Impeller:** on, and nothing disables it (no `EnableImpeller` key in `AndroidManifest.xml`).
- **Images:** decoded at display size. Attachment thumbnails use `cacheWidth`, and the GitHub marks are pre-decoded.
- **Git refreshes:** debounced (300 ms, one at a time) in `lib/git/git_repo.dart`.
- **Chat:** Markdown parses once per change (`parsedMarkdown` cache), and each block paints on its own layer.
- **Terminal:** cached rendered lines, behind a RepaintBoundary.
- **Expensive effects:** no `BackdropFilter`, `ShaderMask` or `ColorFilter` anywhere.
- **Icons:** the font is subset to the app's icons (about 120 KB).

Found:

1. **Every APK is a debug build.** `.github/workflows/build.yml` runs `flutter build apk --debug`. The 48 MB APK (compressed sizes, 14 October build) breaks down as:

   | Part | Size | In a release build |
   |---|---|---|
   | `assets/flutter_assets/kernel_blob.bin` (JIT kernel) | 16.9 MB | Gone (replaced by AOT `libapp.so`) |
   | `lib/arm64-v8a/libflutter.so` (debug engine) | 15.7 MB | The much smaller release engine |
   | `lib/arm64-v8a/libVkLayer_khronos_validation.so` (Vulkan validation) | 4.6 MB | Gone |
   | `assets/flutter_assets/isolate_snapshot_data` | 4.4 MB | Gone |
   | `classes.dex` | 2.9 MB | Shrunk by R8 |
   | Our assets (editor bundle 1.77 MB raw, fonts 1.3 MB raw) | 2.0 MB | Same |
   | `libaiterm-needle.so`, proot, talloc | 1.0 MB | Same |

   A debug app is also marked debuggable, so Android doesn't fully optimise the Kotlin side either. Release signing already uses the shared key: `android/app/build.gradle.kts`, `buildTypes.release` uses `signingConfigs.debug`, which reads `AITERM_KEYSTORE`.

2. **Blocks re-diff files on every frame.** `lib/agents/blocks/blocks_view.dart`, in `_ToolBlock.build`, runs `lineDiff(d.oldText, d.newText)` for every diff. That's longest-common-subsequence work, up to 4 million cells per diff, run for every visible edit block on every rebuild. While a reply streams, the chat rebuilds up to once a frame.

3. **All four app tabs are built at launch.** In `lib/app/home_shell.dart`, `_screens` (Projects, Terminal, Files, Settings) all go into `FadeIndexedStack`, and `IndexedStack` builds every child: Files lists a folder, Terminal mounts its session, Settings builds every group. The workspace (`lib/projects/project_screen.dart`) already builds its tabs lazily (`_built`).

4. **The workspace rebuilds wholesale.** `lib/projects/project_screen.dart` wraps the whole workspace in `Listenable.merge([_s.projects, _nav, _s.tabs, _s.agents, _s.preview, _s.chats, _repo])`. `TerminalTabs` notifies on every session's activity change (`s.activity.addListener(notifyListeners)` in `lib/terminal/terminal_tabs.dart`), so a working/idle flip rebuilds the app bar, the bottom tabs and every built tab.

5. **Startup waits on more than the first frame needs.** `AppServices.load()` (`lib/app/services.dart`) awaits settings, Linux, tabs, reattach, projects, the wallpaper accent and agent sessions. The constructor then starts keep-alive checks, SSH keys, phone grants and port polling at once. Only the theme, tabs and projects are needed for the first frame.

6. **Terminal scrollback is 10,000 lines per tab.** `_AppTerminal() : super(maxLines: 10000)` in `lib/terminal/terminal_session.dart`. That's roughly 16 bytes × columns × lines, about 10 MB for a full tab at 60 columns. Termux keeps 2,000 lines by default.

7. **Port checks every 3 seconds.** `lib/preview/preview_controller.dart` probes the common dev ports and hinted ports over TCP every 3 s while the app is visible, with nothing slower when idle.

8. **Tab fades use Opacity layers.** `lib/shared/fade_indexed_stack.dart` fades the incoming tab with `Opacity`, an offscreen layer over the whole screen for 220 ms, and the terminal deck and home shell use it too.

## Plan

In order. Each item is in [TODO.md](../TODO.md).

- [ ] **P1. Ship release builds (AOT).** Switch `build.yml` to `flutter build apk --release` with the same key. Add R8 keep rules for our Kotlin plugins and JNI classes (`com.aiterm.aiterm.**`: PtyPlugin, NeedlePlugin, PhoneFilesPlugin, keep-alive, backup, SSH) so shrinking can't rename what native code and channels look up. Keep the signature check. Measure the APK before and after, and check on a device that the terminal, Linux install, agents, phone files, the editor and SSH still work.
- [ ] **P2. Compute each diff once.** Keep the result of `lineDiff` with its `ToolDiff` (computed when the update arrives, or memoised on first build); move very large diffs to an isolate (`compute`).
- [ ] **P3. Build app tabs lazily.** Build Terminal, Files and Settings on first visit (like `_built` in the workspace), keeping each one's state afterwards.
- [ ] **P4. Narrow the workspace rebuilds.** Give each bottom-tab badge its own listener, keep the app bar on `_repo` only, and stop rebuilding the terminal deck on activity changes. Expose a separate notifier for "any tab needs input" instead of routing every activity change through `TerminalTabs`.
- [ ] **P5. Start only what the first frame needs.** After the first frame (`addPostFrameCallback`), start keep-alive, SSH keys, phone grants, port polling and agent-session loading.
- [ ] **P6. Lower the terminal scrollback** to 5,000 lines (or make it a setting). Check that agents' long output still scrolls back far enough.
- [ ] **P7. Poll ports less when nothing runs.** Back off to around 10 s when no port has been seen or hinted, and check at once when a session mentions a port, as now.
- [ ] **P8. Cheaper tab transitions.** Use `FadeTransition` with a short duration, or no fade for top-level tabs, so the whole screen isn't redrawn offscreen.
- [ ] **P9. Show frame timings on the phone.** A "Show frame timings" switch in Settings → About sets `MaterialApp.showPerformanceOverlay`, so frame times can be checked in release builds on the phone. Optionally, a manual CI workflow that builds a profile APK for DevTools sessions.

### How to verify

- **Before and after:** APK size from the release asset, and cold start (process start to first frame, from `adb shell am start -W` or the logcat "Displayed" time).
- **Frame times** with the performance overlay (P9) while:
  - scrolling a long terminal,
  - streaming an agent reply in blocks with a few edit diffs open,
  - switching app and workspace tabs,
  - opening the editor.
  The target is both graphs under 8 ms on the phone.
- **Memory:** the app's Total PSS (`adb shell dumpsys meminfo com.aiterm.aiterm`) with three terminal tabs and a blocks chat open.
