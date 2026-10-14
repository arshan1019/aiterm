import 'dart:io';
import 'package:flutter/material.dart';
import '../assistant/assistant.dart';
import '../assistant/needle.dart';
import '../assistant/tool_call.dart';
import '../agents/acp/acp_agents.dart';
import '../agents/acp/agent_chat.dart';
import '../agents/acp/agent_chats.dart';
import '../agents/acp/attachments.dart';
import '../agents/agent_catalog.dart';
import '../agents/agent_installer.dart';
import '../backup/backup_controller.dart';
import '../keep_alive/keep_alive_controller.dart';
import '../onboarding/setup_pipeline.dart';
import '../linux/linux_environment.dart';
import '../phone/phone_files.dart';
import '../platform/android_env.dart';
import '../platform/system_colors.dart';
import '../settings/settings.dart';
import '../ssh/ssh_keys.dart';
import '../git/git_registry.dart';
import '../git/git_runner.dart';
import '../git/git_tools.dart';
import '../git/github_auth.dart';
import '../git/linux_process.dart';
import '../platform/pty.dart';
import '../projects/project.dart';
import '../projects/project_service.dart';
import '../projects/project_store.dart';
import '../shared/format.dart';
import '../terminal/terminal_session.dart';
import '../preview/preview_controller.dart';
import '../terminal/session_presence.dart';
import '../terminal/terminal_tabs.dart';
import 'navigation.dart';
import 'theme.dart';

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
      // The wallpaper may have changed meanwhile.
      onResume: () {
        keepAlive.refresh().ignore();
        _readAccent().ignore();
      },
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
      final agent = agents.installed
          .where((a) => session.agent == a.id || (session.agent == null && session.title.startsWith(a.name)))
          .firstOrNull;
      if (agent != null) _offerReview(session, agent.name, cwd).ignore();
    };
    agents.openAsBlocks = _openAsBlocks;
    // A removed project's sessions move to the Terminal tab.
    projects.addListener(_reconcileTabs);
    ssh.load().ignore();
    phone.refresh().ignore();
    if (linux.installed) preview.start().ignore();
    _updatePresence();
  }

  final _presence = SessionPresence(setVisible: PtyHost.instance.setVisible, setTitle: PtyHost.instance.setTitle);
  bool _appVisible = true;

  void _updatePresence() {
    _presence.update(
      visibleId: visibleSession(appVisible: _appVisible, shownPtyId: shownSession?.ptyId),
      titles: {for (final t in tabs.tabs) ?t.ptyId: t.title},
    );
  }

  /// The wallpaper's accent (Android 12+), for "Wallpaper colors".
  final systemAccent = ValueNotifier<Color?>(null);

  Future<void> _readAccent() async => systemAccent.value = await SystemColors.accent();

  /// The app's theme for [dark], with the user's appearance settings.
  ThemeData theme({required bool dark}) => buildTheme(
        dark: dark,
        seed: settings.wallpaperColors ? systemAccent.value : null,
        compact: settings.compact,
        highContrast: settings.highContrast,
      );

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

  /// Agent chats as blocks (ACP), when Settings turns them on.
  late AgentChats chats = AgentChats(File('${paths.filesDir}/agent_sessions.json'), (agent, cwd) {
    final acp = AcpAgent.of(agent)!;
    return AgentChat(
      agent: acp,
      name: AgentInstaller.recipe(agent).name,
      cwd: cwd,
      start: (a, cwd) => LinuxAcpTransport.start(linux, a, cwd),
      prepare: (a, onOutput) => LinuxAcpTransport.prepare(linux, a, onOutput),
      sessions: chats,
      preferred: {
        for (final option in const ['mode', 'model']) option: ?settings.agentOption(agent, option),
      },
      onOptionChosen: (option, value) => settings.setAgentOption(agent, option, value),
      attachmentsDir: attachmentsDir,
    );
  });

  bool _openAsBlocks(AgentRecipe agent, String? cwd) {
    if (cwd == null || linux.usesAndroidShell || !settings.blocksFor(agent.id) || AcpAgent.of(agent.id) == null) {
      return false;
    }
    () async {
      final project = await projects.usedAgent(cwd, agent.id);
      final path = project?.path ?? cwd;
      chats.open(agent.id, path);
      if (project != null) showProject(project, tab: WorkspaceTab.agent);
    }();
    return true;
  }

  void _refreshAgents() {
    if (linux.installed) agents.refresh().ignore();
  }

  void _startAgent() {
    if (linux.installed) ssh.startAgent(rootfs: linux.rootfs).ignore();
  }

  /// The terminal on screen: the Terminal tab's selected tab, or the open
  /// project's while its agent tab shows. Null when no terminal shows.
  TerminalSession? get shownSession {
    if (navigation.shownProject case final p?) {
      return navigation.workspaceTab == WorkspaceTab.agent ? tabs.activeIn(p.path) : null;
    }
    return navigation.atTabs && navigation.tab == AppTab.terminal ? tabs.activeIn(null) : null;
  }

  /// A notification for session [ptyId] was tapped: show it where it lives.
  void _openSession(int ptyId) {
    final session = tabs.tabs.where((t) => t.ptyId == ptyId).firstOrNull;
    if (session != null) tabs.select(session);
    showSession(session);
  }

  /// Shows [session] where it lives: its project's agent tab, or the
  /// Terminal tab.
  void showSession(TerminalSession? session) {
    final project = session == null ? null : projectOf(session);
    if (project != null) {
      showProject(project, tab: WorkspaceTab.agent);
    } else {
      navigation.open(AppTab.terminal);
    }
  }

  /// Opens [project]'s workspace (and remembers it as most recent).
  void showProject(Project project, {WorkspaceTab? tab}) {
    projects.opened(project).ignore();
    navigation.showProject(ProjectRef(project.id, project.path), tab: tab);
  }

  void _reconcileTabs() {
    for (final path in {for (final t in tabs.tabs) ?t.project}) {
      if (projects.byPath(path) == null) tabs.detachProject(path);
    }
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

  /// Phone folders and files the user chose, and files shared to aiterm.
  final phone = PhoneFiles();
  late final backup = BackupController(BackupChannel(), filesDir: paths.filesDir, appVersion: '1.0.0');
  late final KeepAliveController keepAlive;

  // Projects and git (real git and GitHub's gh inside Linux). Not final so
  // widget tests can swap in fakes before the first frame.
  late GitRegistry git = GitRegistry(LinuxGitRunner(linux.runCommandLine));
  late GitTools gitTools = GitTools(run: linux.runScriptStreaming);
  late GitHubAuth github = GitHubAuth(
    // No terminal: gh prints the code and URL and waits, no prompts.
    startLogin: () => LinuxProcess.start(
        linux, 'BROWSER=true exec gh auth login --hostname github.com --git-protocol https --web --scopes admin:public_key </dev/null'),
    run: (args, {stdin}) =>
        linux.runCommandLine('exec gh ${args.map(shellQuote).join(' ')}', env: gitEnvironment, stdin: stdin),
  );
  late final projects = ProjectStore('${paths.filesDir}/projects.json');
  ProjectService get projectService => ProjectService(store: projects, git: git.runner, hostPath: linux.hostPath);

  /// The project a terminal tab works on, if it's one of the user's.
  Project? projectOf(TerminalSession tab) => switch (tab.project) {
        final path? => projects.byPath(path),
        null => null,
      };

  /// One-tap AI agents; "Open" goes back to the agent's tab for that
  /// folder, or starts one. The folder becomes a recent project.
  late AgentInstaller agents = AgentInstaller(
    run: linux.runScriptStreaming,
    launch: (agent, title, commands, cwd) async {
      // The folder becomes (or is) a project, and the session lives there.
      final project = cwd == null ? null : await projects.usedAgent(cwd, agent.id);
      final scope = project?.path;
      final existing = tabs.findAgent(agent.id, scope);
      if (scope != null) chats.show(scope, AgentView.terminal);
      if (existing == null) {
        tabs.open(title: project == null ? title : agent.name, commands: commands, cwd: cwd, project: scope, agent: agent.id);
      } else {
        tabs.select(existing);
        if (existing.state.value == SessionState.exited) {
          existing.restart(linux.sessionSpec, alpine: !linux.usesAndroidShell).ignore();
        }
      }
      showSession(tabs.active);
    },
  );

  /// Start downloading Linux as soon as first-run setup shows. Off under
  /// `flutter test`, where nothing may hit the network.
  final prefetchLinux = !Platform.environment.containsKey('FLUTTER_TEST');

  /// First run: Linux, git tools and the chosen agents in one go.
  late SetupPipeline setup = SetupPipeline(
    installLinux: linux.install,
    linuxReady: () => linux.installed,
    installTools: () async => await gitTools.ensure() ? null : gitTools.error ?? 'Couldn\'t install git.',
    installAgent: (id) async {
      await agents.install(id);
      final state = agents.stateOf(id);
      return state.status == AgentStatus.installed ? null : state.message ?? 'Install failed.';
    },
    agentName: (id) => AgentInstaller.recipe(id).name,
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
    await (services.projects.load(), services._readAccent(), services.chats.load()).wait;
    services._reconcileTabs();
    return services;
  }

  /// Runs an app action the assistant picked ("dark mode", "bigger text",
  /// "show src in files", "restart the shell").
  void perform(ToolCall action) {
    switch (action.tool) {
      case 'set_font_size':
        settings.stepFontSize(action.args['change'] == 'smaller' ? -1 : 1);
      case 'set_theme':
        settings.theme = action.args['theme'] == 'light' ? ThemeChoice.light : ThemeChoice.dark;
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
