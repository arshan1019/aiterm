import 'package:flutter/material.dart';
import '../agents/agent_catalog.dart';
import '../agents/agent_installer.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../files/files_screen.dart';
import '../git/git_repo.dart';
import '../git/git_screen.dart';
import '../preview/preview_screen.dart';
import '../shared/action_sheet.dart';
import '../shared/fade_indexed_stack.dart';
import '../shared/format.dart';
import '../shared/bottom_tabs.dart';
import '../terminal/terminal_deck.dart';
import 'project.dart';
import 'project_actions.dart';
import 'projects_screen.dart';

/// Opens [project]'s workspace over Projects (and remembers it as most
/// recent).
void openProject(BuildContext context, Project project) => context.services.showProject(project);

Route<void> projectRoute(ProjectRef ref) => MaterialPageRoute<void>(
      settings: RouteSettings(name: AppNavigation.projectRouteName, arguments: ref),
      builder: (_) => ProjectScreen(project: ref),
    );

/// A project's workspace: everything for the project in one place, as
/// tabs. agent (its agent and terminal sessions), changes (git), files
/// (its folder), preview (its dev server). Opens on agent; back steps
/// through a tab's own history, then to agent, then out to Projects.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.project});

  final ProjectRef project;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final _s = context.services;
  late final _nav = _s.navigation;
  GitRepo? _repo;

  /// Tabs are built the first time they're shown, then kept.
  final _built = <WorkspaceTab>{};

  Project? get _project => _s.projects.projects.where((p) => p.id == widget.project.id).firstOrNull;

  @override
  void initState() {
    super.initState();
    _s.gitTools.addListener(_findRepo);
    _findRepo();
  }

  @override
  void dispose() {
    _s.gitTools.removeListener(_findRepo);
    super.dispose();
  }

  Future<void> _findRepo() async {
    if (!_s.gitTools.ready || _repo != null) return;
    final repo = await _s.git.repoFor(widget.project.path);
    if (!mounted || repo == null) return;
    setState(() => _repo = repo);
    await repo.refresh();
  }

  Future<void> _back() async {
    if (!await _nav.handleWorkspaceBack() && mounted) Navigator.pop(context);
  }

  /// The + in the agent tab: an agent (back to it if it's open) or a
  /// terminal, in this project.
  void _newSession(Project p) {
    final installed = _s.agents.installed;
    showActionSheet(context, title: 'New in ${p.name}', actions: [
      for (final a in installed)
        SheetAction(Icons.auto_awesome_rounded, _s.tabs.findAgent(a.id, p.path) == null ? a.name : 'Back to ${a.name}',
            () => _s.agents.open(a.id, cwd: p.path),
            accent: true),
      if (installed.isEmpty)
        SheetAction(Icons.auto_awesome_rounded, 'Install ${agentCatalog.first.name}',
            () => _s.agents.open(agentCatalog.first.id, cwd: p.path),
            accent: true),
      SheetAction(Icons.terminal_rounded, 'Terminal', () => _s.tabs.open(cwd: p.path, project: p.path)),
    ]);
  }

  List<BottomTab> _tabs() {
    final changed = _repo?.status?.changes.length ?? 0;
    return [
      const BottomTab('Agent', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
      BottomTab('Changes', Icons.call_split_outlined, Icons.call_split_rounded, badge: changed > 0 ? '$changed' : null),
      const BottomTab('Files', Icons.folder_outlined, Icons.folder_rounded),
      BottomTab('Preview', Icons.wifi_tethering_outlined, Icons.wifi_tethering_rounded,
          badge: _s.preview.livePorts.isEmpty ? null : ''),
    ];
  }

  Widget _content(WorkspaceTab t, Project p) => switch (t) {
        WorkspaceTab.agent => _s.tabs.inScope(p.path).isEmpty
            ? _AgentLauncher(project: p, onTerminal: () => _s.tabs.open(cwd: p.path, project: p.path))
            : TerminalDeck(
                project: p.path,
                showing: _nav.workspaceTab == WorkspaceTab.agent && _nav.shownProject?.id == p.id,
                onNew: () => _newSession(p),
                onReview: (_) => _nav.openWorkspaceTab(WorkspaceTab.changes),
                onPreview: (_) => _nav.openWorkspaceTab(WorkspaceTab.preview),
                onGitHere: (_) => _nav.openWorkspaceTab(WorkspaceTab.changes),
              ),
        WorkspaceTab.changes => GitScreen(folder: p.path, title: p.name, embedded: true),
        WorkspaceTab.files => FilesScreen(project: widget.project, projectName: p.name),
        WorkspaceTab.preview => _PreviewTab(onAgent: () => _nav.openWorkspaceTab(WorkspaceTab.agent)),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([_s.projects, _nav, _s.tabs, _s.agents, _s.preview, ?_repo]),
      builder: (context, _) {
        final p = _project;
        if (p == null) return const Scaffold();
        final tab = _nav.workspaceTab;
        _built.add(tab);
        final status = _repo?.status;
        final sync = [
          if ((status?.behind ?? 0) > 0) '↓${status!.behind}',
          if ((status?.ahead ?? 0) > 0) '↑${status!.ahead}',
        ].join(' ');
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, overflow: TextOverflow.ellipsis),
                  Text(
                    status?.branch != null ? [status!.branch!, if (sync.isNotEmpty) sync].join('  ') : shortPath(p.path),
                    style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
              actions: [
                IconButton(tooltip: 'Project actions', icon: const Icon(Icons.more_vert_rounded), onPressed: () => showProjectActions(context, p, showOpen: false)),
              ],
            ),
            bottomNavigationBar: BottomTabs(
              tabs: _tabs(),
              selected: tab.index,
              onSelect: (i) => _nav.openWorkspaceTab(WorkspaceTab.values[i]),
            ),
            body: FadeIndexedStack(
              index: tab.index,
              children: [
                for (final t in WorkspaceTab.values) _built.contains(t) ? _content(t, p) : const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The agent tab before anything runs in it: open the project's agent
/// (the one used here last), another agent, or a plain terminal.
class _AgentLauncher extends StatelessWidget {
  const _AgentLauncher({required this.project, required this.onTerminal});

  final Project project;
  final VoidCallback onTerminal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final installer = context.services.agents;
    final installed = installer.installed;
    final main = installed.where((a) => a.id == project.agentId).firstOrNull ?? installed.firstOrNull;
    final others = [for (final a in installed) if (a != main) a];
    final busy = [for (final a in agentCatalog) if (installer.stateOf(a.id).status == AgentStatus.installing) a];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: [
            Icon(Icons.auto_awesome_rounded, size: 36, color: c.accent),
            const SizedBox(height: 20),
            // Only state is worth words here: an install in progress.
            if (busy.isNotEmpty) ...[
              Text(
                '${busy.first.name}: ${installer.stateOf(busy.first.id).step ?? 'Installing'}…',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            if (main == null) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: installer.busy ? null : () => installer.open(agentCatalog.first.id, cwd: project.path),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('Install ${agentCatalog.first.name}'),
              ),
              TextButton(onPressed: () => openAgents(context), child: const Text('Other agents')),
            ] else ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => installer.open(main.id, cwd: project.path),
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: Text('Open ${main.name}'),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  for (final a in others)
                    TextButton(onPressed: () => installer.open(a.id, cwd: project.path), child: Text('Open ${a.name}')),
                  if (installed.length < agentCatalog.length)
                    TextButton(
                      onPressed: () => openAgents(context),
                      child: Text('More agents', style: TextStyle(color: c.textMuted)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTerminal,
              icon: const Icon(Icons.terminal_rounded, size: 18),
              label: const Text('Terminal'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview tab: the dev server running in Linux, or how to start one.
class _PreviewTab extends StatefulWidget {
  const _PreviewTab({required this.onAgent});
  final VoidCallback onAgent;

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab> {
  int? _port;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ports = context.services.preview.livePorts.toList()..sort();
    if (ports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_tethering_rounded, size: 40, color: c.textMuted),
              const SizedBox(height: 12),
              Text('No server running', style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: widget.onAgent, child: const Text('Go to agent')),
            ],
          ),
        ),
      );
    }
    final port = ports.contains(_port) ? _port! : ports.first;
    return Column(
      children: [
        if (ports.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                for (final p in ports)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(':$p'), selected: p == port, onSelected: (_) => setState(() => _port = p)),
                  ),
              ],
            ),
          ),
        Expanded(child: PreviewScreen(key: ValueKey(port), port: port, embedded: true)),
      ],
    );
  }
}
