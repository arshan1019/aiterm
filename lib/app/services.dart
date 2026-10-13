import 'package:flutter/widgets.dart';
import '../assistant/assistant.dart';
import '../assistant/needle.dart';
import '../assistant/tool_call.dart';
import '../agents/agent_installer.dart';
import '../backup/backup_controller.dart';
import '../keep_alive/keep_alive_controller.dart';
import '../linux/linux_environment.dart';
import '../platform/android_env.dart';
import '../settings/settings.dart';
import '../ssh/ssh_keys.dart';
import '../git/git_registry.dart';
import '../git/git_runner.dart';
import '../git/git_tools.dart';
import '../git/github_auth.dart';
import '../git/pty_process.dart';
import '../platform/pty.dart';
import '../projects/project_service.dart';
import '../projects/project_store.dart';
import '../shared/format.dart';
import '../terminal/terminal_session.dart';
import '../preview/preview_controller.dart';
import '../terminal/session_presence.dart';
import '../terminal/terminal_tabs.dart';
import 'navigation.dart';

/// Everything the app's screens share, created once at startup and handed
/// down through [AppScope]. Plain objects with explicit dependencies; no
/// hidden singletons.
class AppServices {
  AppServices._(this.paths, this.settings, this.linux, this.tabs)
      : navigation = AppNavigation(),
        assistant = Assistant(Needle(paths)) {
    keepAlive = KeepAliveController(
      platform: KeepAliveChannel(),
      runInLinux: linux.runScript,
      isFixed: () => settings.childLimitFixed,
      markFixed: settings.markChildLimitFixed,
    );
    // Android may kill a backgrounded app without warning: save tabs as
    // soon as the app leaves the screen.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        preview.stop();
        _appVisible = false;
        _updatePresence();
        tabs.save().ignore();
      },
      onShow: () {
        if (linux.installed) preview.start().ignore();
        _appVisible = true;
        _updatePresence();
      },
      // Back from battery or notification settings: show the new state.
      onResume: () => keepAlive.refresh().ignore(),
    );
    navigation.addListener(_updatePresence);
    tabs.addListener(_updatePresence);
    PtyHost.instance.onOpenRequest = _openSession;
    tabs.onPortsMentioned = preview.portsMentioned;
    linux.addListener(_startAgent);
    _startAgent();
    linux.addListener(_refreshAgents);
    _refreshAgents();
    linux.addListener(_refreshGit);
    _refreshGit();
    tabs.onSignal = (session, signal) {
      final cwd = session.cwd;
      if (cwd == null) return;
      // A command finished in a terminal: its repo may have changed.
      if (signal is CommandSignal) git.touched(cwd);
      // An agent finished (exited, or asked for attention): offer a review.
      final agent = agents.installed.where((a) => session.title.startsWith(a.name)).firstOrNull;
      if (agent != null) _offerReview(session, agent.name, cwd).ignore();
    };
    ssh.load().ignore();
    if (linux.installed) preview.start().ignore();
    _updatePresence();
  }

  final _presence = SessionPresence(setVisible: PtyHost.instance.setVisible, setTitle: PtyHost.instance.setTitle);
  bool _appVisible = true;

  void _updatePresence() {
    _presence.update(
      visibleId: visibleSession(appVisible: _appVisible, tab: navigation.tab, activePtyId: tabs.active.ptyId),
      titles: {for (final t in tabs.tabs) ?t.ptyId: t.title},
    );
  }

  void _refreshGit() {
    if (!linux.installed) return;
    gitTools.refresh().then((_) {
      if (gitTools.ready) github.refresh();
    }).ignore();
  }

  Future<void> _offerReview(TerminalSession session, String agent, String cwd) async {
    if (!gitTools.ready) return;
    final repo = await git.repoFor(cwd);
    if (repo == null) return;
    await repo.refresh();
    final n = repo.status?.changes.length ?? 0;
    session.review.value = n == 0 ? null : ReviewHint('${plural(n, 'file')} changed · $agent', repo.path);
  }

  void _refreshAgents() {
    if (linux.installed) agents.refresh().ignore();
  }

  void _startAgent() {
    if (linux.installed) ssh.startAgent(rootfs: linux.rootfs).ignore();
  }

  /// A notification for session [ptyId] was tapped.
  void _openSession(int ptyId) {
    for (final t in tabs.tabs) {
      if (t.ptyId == ptyId) tabs.select(t);
    }
    navigation.open(AppTab.terminal);
  }

  // ignore: unused_field
  late final AppLifecycleListener _lifecycle;

  final AppPaths paths;
  final Settings settings;
  final AppNavigation navigation;
  final LinuxEnvironment linux;
  final TerminalTabs tabs;
  final Assistant assistant;
  final preview = PreviewController();
  final ssh = SshKeys(SshChannel());
  late final backup = BackupController(BackupChannel(), filesDir: paths.filesDir, appVersion: '1.0.0');
  late final KeepAliveController keepAlive;

  // Projects and git (real git and GitHub's gh inside Linux). Not final so
  // widget tests can swap in fakes before the first frame.
  late GitRegistry git = GitRegistry(LinuxGitRunner(linux.runCommandLine));
  late GitTools gitTools = GitTools(run: linux.runScriptStreaming);
  late GitHubAuth github = GitHubAuth(
    startLogin: () => PtyProcess.start(linux, 'BROWSER=true exec gh auth login -h github.com -p https --web -s admin:public_key'),
    run: (args, {stdin}) =>
        linux.runCommandLine('exec gh ${args.map(shellQuote).join(' ')}', env: gitEnvironment, stdin: stdin),
  );
  late final projects = ProjectStore('${paths.filesDir}/projects.json');
  ProjectService get projectService => ProjectService(store: projects, git: git.runner, hostPath: linux.hostPath);

  /// One-tap AI agents; "Open" starts one in its own terminal tab.
  late final agents = AgentInstaller(
    run: linux.runScriptStreaming,
    launch: (title, commands, cwd) {
      tabs.open(title: title, commands: commands, cwd: cwd);
      navigation.open(AppTab.terminal);
    },
  );

  /// Loads everything the first frame depends on.
  static Future<AppServices> load() async {
    final paths = await AndroidEnv.paths();
    final linux = LinuxEnvironment(paths);
    final tabs = TerminalTabs(paths.filesDir);
    final (settings, _, _) = await (Settings.load(paths.filesDir), linux.load(), tabs.load()).wait;
    // Shells that kept running while the UI was gone (the app was swiped
    // away) are picked up again before the first frame.
    await tabs.reattach();
    final services = AppServices._(paths, settings, linux, tabs);
    services.keepAlive.refresh().ignore();
    await services.projects.load();
    return services;
  }

  /// Runs an app action the assistant picked ("dark mode", "bigger text",
  /// "show src in files", "restart the shell").
  void perform(ToolCall action) {
    switch (action.tool) {
      case 'set_font_size':
        settings.stepFontSize(action.args['change'] == 'smaller' ? -1 : 1);
      case 'set_theme':
        settings.dark = action.args['theme'] != 'light';
      case 'open_tab':
        navigation.open(switch (action.args['tab']) {
          'files' => AppTab.files,
          'settings' => AppTab.settings,
          _ => AppTab.terminal,
        });
      case 'show_in_files':
        navigation.showFolder(action.args['path'] ?? '~');
      case 'restart_shell':
        tabs.active.restart(linux.sessionSpec, alpine: !linux.usesAndroidShell);
    }
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

extension ServicesContext on BuildContext {
  AppServices get services => AppScope.of(this);
}
