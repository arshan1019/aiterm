# aiterm

Run AI coding agents (Claude Code, Gemini CLI, Codex CLI) natively on an Android phone, on real projects: one-tap agent installs, project workspaces, git and GitHub, a full terminal and a file manager, all on Alpine Linux under proot.

- [User flow](docs/USERFLOW.md): how people use the app, where it costs effort, and the flow we're building towards (with diagrams).
- APKs are built by GitHub Actions (`.github/workflows/build.yml`) and published as the `debug-latest` release.
- Code map: see the comment at the top of `lib/main.dart`.
