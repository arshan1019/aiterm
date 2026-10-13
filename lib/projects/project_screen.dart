import 'dart:io';
import 'package:flutter/material.dart';
import '../agents/agent_catalog.dart';
import '../agents/agent_installer.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../files/file_clipboard.dart';
import '../files/file_system_service.dart';
import '../git/git_actions.dart';
import '../git/git_repo.dart';
import '../git/git_screen.dart';
import '../platform/android_env.dart';
import '../preview/preview_screen.dart';
import '../shared/action_sheet.dart';
import '../shared/format.dart';
import '../shared/name_dialog.dart';
import 'project.dart';

/// Opens [project]'s workspace (and remembers it as most recent).
Future<void> openProject(BuildContext context, Project project) {
  context.services.projects.opened(project).ignore();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(projectId: project.id)));
}

/// A project's workspace: its agents, git changes, terminal, files and
/// preview, all starting in the project's folder.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final _s = context.services;
  GitRepo? _repo;
  bool _repoChecked = false;

  Project? get _project => _s.projects.projects.where((p) => p.id == widget.projectId).firstOrNull;

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
    final p = _project;
    if (p == null || !_s.gitTools.ready) return;
    final repo = await _s.git.repoFor(p.path);
    if (!mounted) return;
    setState(() {
      _repo = repo;
      _repoChecked = true;
    });
    if (repo != null) await repo.refresh();
  }

  Future<void> _startTracking(Project p) async {
    final r = await _s.git.runner.run(p.path, ['init', '-q']);
    if (!r.ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapGitError(r).message)));
      return;
    }
    _s.git.forget(p.path);
    await _findRepo();
  }

  void _openChanges(Project p) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GitScreen(folder: p.path, title: p.name)));

  void _menu(Project p) {
    showActionSheet(context, title: p.name, actions: [
      SheetAction(Icons.drive_file_rename_outline_rounded, 'Rename', () async {
        final name = await showNameDialog(context, title: 'Rename project', action: 'Rename', initial: p.name);
        if (name != null) await _s.projects.rename(p, name);
      }),
      SheetAction(Icons.folder_open_rounded, 'Show in Files', () => _s.navigation.showFolder(p.path)),
      SheetAction(Icons.smartphone_rounded, 'Copy to phone (Download)', () => _export(p)),
      null,
      SheetAction(Icons.playlist_remove_rounded, 'Remove from projects', () => _remove(p)),
      SheetAction(Icons.delete_outline_rounded, 'Delete project and files', () => _delete(p), danger: true),
    ]);
  }

  Future<void> _export(Project p) async {
    final messenger = ScaffoldMessenger.of(context);
    var access = false;
    try {
      access = await AndroidEnv.storageAccess();
    } catch (_) {}
    if (!access) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Allow access to phone storage first.'),
        action: SnackBarAction(label: 'Allow', onPressed: AndroidEnv.requestStorageAccess),
      ));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Copying to phone…')));
    final clip = FileClipboard()
      ..copy([
        FsEntry(name: p.path.split('/').last, path: _s.linux.hostPath(p.path), kind: EntryKind.directory, size: 0, modified: DateTime.now()),
      ]);
    try {
      final done = await clip.paste('/storage/emulated/0/Download');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Copied to Download/${done.first.split('/').last}')));
    } on FileSystemException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      clip.dispose();
    }
  }

  Future<void> _remove(Project p) async {
    final ok = await _confirm('Remove “${p.name}”?', 'It leaves the list. Its folder ${shortPath(p.path)} stays as it is.', 'Remove');
    if (!ok || !mounted) return;
    Navigator.pop(context);
    await _s.projects.remove(p);
  }

  Future<void> _delete(Project p) async {
    final ok = await _confirm('Delete “${p.name}”?',
        'The folder ${shortPath(p.path)} and everything in it, including unpushed commits, will be deleted. This can\'t be undone.',
        'Delete');
    if (!ok || !mounted) return;
    Navigator.pop(context);
    await _s.projects.remove(p);
    try {
      await Directory(_s.linux.hostPath(p.path)).delete(recursive: true);
    } on FileSystemException catch (_) {}
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([_s.projects, _s.agents, _s.gitTools, _s.preview, ?_repo]),
      builder: (context, _) {
        final p = _project;
        if (p == null) return const Scaffold();
        final ports = _s.preview.livePorts;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, overflow: TextOverflow.ellipsis),
                Text(shortPath(p.path), style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: [
              IconButton(tooltip: 'Project actions', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _menu(p)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Card(title: 'Agents', children: [
                for (final agent in agentCatalog) _AgentRow(agent: agent, project: p),
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Changes', children: [_changes(context, p)]),
              const SizedBox(height: 12),
              _Card(title: 'Workspace', children: [
                ListTile(
                  leading: Icon(Icons.terminal_rounded, color: c.accent, size: 20),
                  title: const Text('Terminal', style: TextStyle(fontSize: 14)),
                  subtitle: Text('A new tab in this folder', style: TextStyle(color: c.textMuted, fontSize: 12)),
                  onTap: () {
                    _s.tabs.open(cwd: p.path);
                    _s.navigation.open(AppTab.terminal);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.folder_rounded, color: c.accent, size: 20),
                  title: const Text('Files', style: TextStyle(fontSize: 14)),
                  subtitle: Text('Browse, copy in assets from your phone', style: TextStyle(color: c.textMuted, fontSize: 12)),
                  onTap: () => _s.navigation.showFolder(p.path),
                ),
                if (ports.isEmpty)
                  ListTile(
                    enabled: false,
                    leading: Icon(Icons.wifi_tethering_rounded, color: c.textMuted, size: 20),
                    title: const Text('Preview', style: TextStyle(fontSize: 14)),
                    subtitle: Text('Start a dev server and it shows up here', style: TextStyle(color: c.textMuted, fontSize: 12)),
                  )
                else
                  for (final port in ports)
                    ListTile(
                      leading: Icon(Icons.wifi_tethering_rounded, color: c.accent, size: 20),
                      title: Text('Preview localhost:$port', style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PreviewScreen(port: port))),
                    ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _changes(BuildContext context, Project p) {
    final c = context.colors;
    final tools = _s.gitTools;
    if (!tools.ready) {
      return ListTile(
        leading: Icon(Icons.history_rounded, color: c.textMuted, size: 20),
        title: const Text('Track changes with git', style: TextStyle(fontSize: 14)),
        subtitle: Text('Review, commit and sync with GitHub', style: TextStyle(color: c.textMuted, fontSize: 12)),
        trailing: OutlinedButton(
          onPressed: () async {
            if (await ensureGitTools(context)) _findRepo();
          },
          child: const Text('Set up'),
        ),
      );
    }
    final repo = _repo;
    if (!_repoChecked) return const SizedBox(height: 56);
    if (repo == null) {
      return ListTile(
        leading: Icon(Icons.history_rounded, color: c.textMuted, size: 20),
        title: const Text('Not tracked by git', style: TextStyle(fontSize: 14)),
        trailing: OutlinedButton(onPressed: () => _startTracking(p), child: const Text('Start tracking')),
      );
    }
    final s = repo.status;
    final changed = s?.changes.length ?? 0;
    final sync = [
      if ((s?.behind ?? 0) > 0) '↓${s!.behind}',
      if ((s?.ahead ?? 0) > 0) '↑${s!.ahead}',
    ].join(' ');
    return ListTile(
      leading: Icon(Icons.call_split_rounded, color: c.accent, size: 20),
      title: Text(
        s == null ? 'Reading…' : (changed == 0 ? 'No changes' : '${plural(changed, 'changed file')} to review'),
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        [
          s?.branch ?? '',
          if (sync.isNotEmpty) sync,
          if (s?.lastCommit case final last?) '${last.subject} · ${timeAgo(last.time)}',
        ].where((x) => x.isNotEmpty).join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted),
      onTap: () => _openChanges(p),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text(title.toUpperCase(),
                style: TextStyle(color: c.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.project});

  final AgentRecipe agent;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final installer = context.services.agents;
    final state = installer.stateOf(agent.id);
    return ListTile(
      leading: Icon(Icons.auto_awesome_rounded, color: state.status == AgentStatus.installed ? c.accent : c.textMuted, size: 20),
      title: Text(agent.name, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        switch (state.status) {
          AgentStatus.installing => '${state.step ?? 'Installing'}…',
          AgentStatus.failed => state.message ?? 'Install failed',
          _ => agent.vendor,
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: state.status == AgentStatus.failed ? c.danger : c.textMuted, fontSize: 12),
      ),
      trailing: AnimatedSwitcher(
        duration: Motion.quick,
        child: switch (state.status) {
          AgentStatus.installed => FilledButton(
              key: const ValueKey('open'),
              onPressed: () => installer.open(agent.id, cwd: project.path),
              child: const Text('Open'),
            ),
          AgentStatus.installing => const SizedBox(
              key: ValueKey('busy'), width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          _ => OutlinedButton(
              key: const ValueKey('install'),
              onPressed: installer.busy ? null : () => installer.install(agent.id),
              child: Text(state.status == AgentStatus.failed ? 'Retry' : 'Install'),
            ),
        },
      ),
    );
  }
}
