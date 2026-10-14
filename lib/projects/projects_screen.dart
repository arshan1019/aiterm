import 'package:flutter/material.dart';
import '../agents/agent_installer.dart';
import '../agents/agents_screen.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../git/git_repo.dart';
import '../preview/preview_screen.dart';
import '../shared/action_sheet.dart';
import '../shared/format.dart';
import '../onboarding/setup_view.dart';
import 'new_project.dart';
import 'project.dart';
import 'project_actions.dart';
import 'project_screen.dart';

/// Home: the user's projects. Each opens a workspace where agents,
/// terminals, files and git start in the project's folder. On first
/// launch, Linux is set up here.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.linux, s.setup]),
      builder: (context, _) => AnimatedSwitcher(
        duration: Motion.standard,
        child: s.linux.installed && !s.setup.active
            ? const _Projects(key: ValueKey('projects'))
            : const SetupView(key: ValueKey('setup')),
      ),
    );
  }
}

class _Projects extends StatelessWidget {
  const _Projects({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([s.projects, s.agents, s.preview, s.tabs]),
        builder: (context, _) {
          final projects = s.projects.projects;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Projects', style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: () => openAgents(context),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Agents'),
                  ),
                ],
              ),
              // A dev server is up: one tap to see it.
              for (final port in s.preview.livePorts)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PreviewChip(port: port),
                ),
              const SizedBox(height: 12),
              if (s.agents.installed.isEmpty) ...[
                const _AgentsPrompt(),
                const SizedBox(height: 12),
              ],
              if (projects.isEmpty)
                const _Empty()
              else
                for (final p in projects) ...[
                  _ProjectCard(key: ValueKey(p.id), project: p),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
      floatingActionButton: ListenableBuilder(
        listenable: s.projects,
        builder: (context, _) => s.projects.projects.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
        onPressed: () => showAddProject(context),
        backgroundColor: c.accent,
        foregroundColor: c.bg,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add project'),
      ),
      ),
    );
  }
}

/// Opens agent [id] in a project the user picks: agents work in projects.
void openAgentInProject(BuildContext context, String id) {
  final s = context.services;
  final projects = s.projects.projects;
  if (projects.isEmpty) return showAddProject(context);
  showActionSheet(context, title: 'Open ${AgentInstaller.recipe(id).name} in', actions: [
    for (final p in projects.take(6)) SheetAction(Icons.folder_rounded, p.name, () => s.agents.open(id, cwd: p.path)),
    null,
    SheetAction(Icons.add_rounded, 'Add project', () => showAddProject(context)),
  ]);
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.port});
  final int port;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
      child: ListTile(
        dense: true,
        leading: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
        minLeadingWidth: 8,
        title: Text('localhost:$port is live', style: TextStyle(color: c.text, fontSize: 13)),
        trailing: Text('Preview', style: TextStyle(color: c.accent, fontSize: 13, fontWeight: FontWeight.w600)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PreviewScreen(port: port))),
      ),
    );
  }
}

/// The agents page, pushed over the tabs.
void openAgents(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('AI agents')), body: const AgentsScreen()),
    ));

class _AgentsPrompt extends StatelessWidget {
  const _AgentsPrompt();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.accent.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.accent.withValues(alpha: 0.4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openAgents(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set up an AI agent', style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Claude Code, Gemini CLI or Codex CLI. One tap installs everything it needs.',
                        style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// No projects yet: the ways to add one, right there (the same list as the
/// Add project button).
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = addProjectActions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 40, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.folder_special_outlined, size: 44, color: c.accent),
          const SizedBox(height: 12),
          Text('No projects yet',
              textAlign: TextAlign.center, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          for (final (i, (icon, label, run)) in actions.indexed) ...[
            if (i == 0)
              FilledButton.icon(onPressed: () => run(context), icon: Icon(icon, size: 18), label: Text(label))
            else
              OutlinedButton.icon(onPressed: () => run(context), icon: Icon(icon, size: 18), label: Text(label)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({super.key, required this.project});
  final Project project;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  late final _s = context.services;
  GitRepo? _repo;

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
    if (repo.status == null) repo.refreshSoon();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.project;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProject(context, p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (onPhoneStorage(p.path)) ...[
                          Icon(Icons.smartphone_rounded, size: 13, color: c.textMuted),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(shortPath(p.path),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textMuted, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_s.tabs.tabs.where((t) => t.project == p.path && t.agent != null).firstOrNull case final tab?) ...[
                      Row(children: [
                        Icon(Icons.auto_awesome_rounded, size: 13, color: c.accent),
                        const SizedBox(width: 4),
                        Text('${AgentInstaller.recipe(tab.agent!).name} open', style: TextStyle(color: c.text, fontSize: 11)),
                      ]),
                      const SizedBox(height: 4),
                    ],
                    if (_repo case final repo?)
                      ListenableBuilder(listenable: repo, builder: (context, _) => _GitLine(repo: repo, opened: p.lastOpened))
                    else
                      Text('Opened ${timeAgo(p.lastOpened)}', style: TextStyle(color: c.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Project actions',
                icon: Icon(Icons.more_vert_rounded, color: c.textMuted),
                onPressed: () => showProjectActions(context, p),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GitLine extends StatelessWidget {
  const _GitLine({required this.repo, required this.opened});
  final GitRepo repo;
  final DateTime opened;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = repo.status;
    final style = TextStyle(color: c.textMuted, fontSize: 11);
    if (s == null) return Text('Opened ${timeAgo(opened)}', style: style);
    final changed = s.changes.length;
    return Row(
      children: [
        Icon(Icons.call_split_rounded, size: 13, color: c.accent),
        const SizedBox(width: 4),
        Flexible(child: Text(s.branch ?? 'detached', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        if (changed > 0) ...[
          const SizedBox(width: 10),
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(plural(changed, 'change'), style: style),
        ],
        if (s.ahead > 0 || s.behind > 0) ...[
          const SizedBox(width: 10),
          Text([if (s.behind > 0) '↓${s.behind}', if (s.ahead > 0) '↑${s.ahead}'].join(' '), style: style),
        ],
      ],
    );
  }
}
