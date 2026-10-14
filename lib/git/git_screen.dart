import 'dart:async';
import 'package:flutter/material.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../shared/action_sheet.dart';
import '../shared/format.dart';
import '../shared/name_dialog.dart';
import '../shared/form.dart';
import 'diff_screen.dart';
import 'commit_message.dart';
import 'git_actions.dart';
import 'git_parsers.dart';
import 'git_repo.dart';

/// A folder's git changes: branch, sync, staged and unstaged files, and
/// commit. A project's Changes tab ([embedded]: no app bar of its own), or
/// a page for folders outside projects (from Files or a terminal tab).
class GitScreen extends StatefulWidget {
  const GitScreen({super.key, required this.folder, this.title, this.embedded = false});

  /// Any folder inside the repository (a guest path).
  final String folder;
  final String? title;
  final bool embedded;

  @override
  State<GitScreen> createState() => _GitScreenState();
}

enum _Load { loading, noTools, notRepo, ready }

class _GitScreenState extends State<GitScreen> {
  late final _s = context.services;
  _Load _load = _Load.loading;
  GitRepo? _repo;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final tools = _s.gitTools;
    await tools.refresh();
    if (!tools.ready) return _set(_Load.noTools);
    final repo = await _s.git.repoFor(widget.folder);
    if (repo == null) return _set(_Load.notRepo);
    _repo = repo;
    _set(_Load.ready);
    await repo.refresh();
    // See what's new on the remote without being asked; quietly, since
    // being offline is fine here.
    if (repo.remotes?.isNotEmpty ?? false) repo.fetch().ignore();
  }

  void _set(_Load l) {
    if (mounted) setState(() => _load = l);
  }

  Future<void> _installTools() async {
    if (await ensureGitTools(context)) _open();
  }

  Future<void> _init() async {
    final r = await _s.git.runner.run(widget.folder, ['init', '-q']);
    if (!r.ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapGitError(r).message)));
      return;
    }
    _s.git.forget(widget.folder);
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repo = _repo;
    final body = switch (_load) {
      _Load.loading => const SizedBox.expand(),
      _Load.noTools => _Message(
          icon: Icons.download_rounded,
          title: 'Git isn\'t set up yet',
          text: 'Install git and GitHub\'s CLI in Linux to track changes and sync. One tap, once.',
          action: 'Install git',
          onAction: _installTools,
        ),
      _Load.notRepo => _Message(
          icon: Icons.history_rounded,
          title: 'Not tracked by git',
          text: 'Start tracking this folder to see changes, commit them and sync with GitHub.',
          action: 'Start tracking',
          onAction: _init,
        ),
      _Load.ready => _RepoView(repo: repo!),
    };
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Changes'),
            Text(widget.title ?? shortPath(repo?.path ?? widget.folder),
                style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [if (repo != null) _RepoMenu(repo: repo)],
      ),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String title, text, action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.accent),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _RepoMenu extends StatelessWidget {
  const _RepoMenu({required this.repo});
  final GitRepo repo;

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return IconButton(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onPressed: () => showActionSheet(context, title: shortPath(repo.path), actions: [
        SheetAction(Icons.call_split_rounded, 'Branches', () => showBranchSheet(context, repo)),
        if (repo.remotes?.isNotEmpty ?? false)
          SheetAction(Icons.cloud_download_outlined, 'Fetch', () => runGit(context, repo.fetch, repo: repo, done: 'Fetched')),
        if (repo.remotes?.isEmpty ?? false)
          SheetAction(Icons.cloud_upload_outlined, 'Publish to GitHub', () => publishToGitHub(context, repo)),
        null,
        SheetAction(Icons.terminal_rounded, 'Open terminal here', () {
          s.tabs.open(cwd: repo.path);
          s.navigation.open(AppTab.terminal);
        }),
        SheetAction(Icons.folder_open_rounded, 'Show in Files', () => s.navigation.showFolder(repo.path)),
        SheetAction(Icons.badge_outlined, 'Commit name & email', () => askCommitIdentity(context)),
      ]),
    );
  }
}

/// Creates a GitHub repository for [repo] and pushes it.
Future<void> publishToGitHub(BuildContext context, GitRepo repo) async {
  final s = context.services;
  if (!(repo.status?.hasCommits ?? false)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commit something first, then publish.')));
    return;
  }
  if (!await signInToGitHub(context) || !context.mounted) return;
  final choice = await showDialog<(String, bool)>(
    context: context,
    builder: (_) => _PublishDialog(name: repo.path.split('/').last),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Publishing…')));
  final r = await s.github.publish(repo.path, name: choice.$1, private: choice.$2);
  repo.remotes = null; // re-read: origin was just added
  await repo.refresh();
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(r.ok ? 'Published to GitHub' : mapGitError(r).message),
  ));
}

class _PublishDialog extends StatefulWidget {
  const _PublishDialog({required this.name});
  final String name;

  @override
  State<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends State<_PublishDialog> {
  late final _name = TextEditingController(text: widget.name);
  bool _private = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _publish() => Navigator.pop(context, (_name.text.trim(), _private));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppDialog(
      title: 'Publish to GitHub',
      message: 'Creates a repository on your GitHub account and pushes this project to it.',
      fields: [
        LabeledField(
          label: 'Repository name',
          child: TextField(controller: _name, autocorrect: false, onChanged: (_) => setState(() {})),
        ),
        Material(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            title: const Text('Private', style: TextStyle(fontSize: 14)),
            subtitle: Text(_private ? 'Only you (and people you invite) can see it' : 'Anyone can see it',
                style: TextStyle(color: c.textMuted, fontSize: 12)),
            value: _private,
            onChanged: (v) => setState(() => _private = v),
          ),
        ),
      ],
      action: 'Publish',
      onAction: _name.text.trim().isEmpty ? null : _publish,
    );
  }
}

/// Switch to a branch, or start a new one.
Future<void> showBranchSheet(BuildContext context, GitRepo repo) async {
  List<GitBranch> branches;
  try {
    branches = await repo.branches();
  } on GitError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  final local = branches.where((b) => !b.remote).toList();
  final localNames = local.map((b) => b.name).toSet();
  // Remote branches without a local one: switching creates it, tracking.
  final remoteOnly = [
    for (final b in branches)
      if (b.remote && !localNames.contains(b.name.substring(b.name.indexOf('/') + 1))) b,
  ];
  await showActionSheet(context, title: 'Branches', actions: [
    SheetAction(Icons.add_rounded, 'New branch…', () async {
      final name = await showNameDialog(context, title: 'New branch', action: 'Create', hint: 'e.g. fix-login');
      if (name != null && context.mounted) {
        await runGit(context, () => repo.createBranch(name.replaceAll(' ', '-')), repo: repo);
      }
    }, accent: true),
    null,
    for (final b in local)
      SheetAction(b.current ? Icons.check_rounded : Icons.call_split_rounded, b.name, () {
        if (!b.current) runGit(context, () => repo.switchBranch(b.name), repo: repo);
      }),
    if (remoteOnly.isNotEmpty) null,
    for (final b in remoteOnly)
      SheetAction(Icons.cloud_outlined, b.name, () {
        runGit(context, () => repo.switchBranch(b.name.substring(b.name.indexOf('/') + 1)), repo: repo);
      }),
  ]);
}

class _RepoView extends StatefulWidget {
  const _RepoView({required this.repo});
  final GitRepo repo;

  @override
  State<_RepoView> createState() => _RepoViewState();
}

class _RepoViewState extends State<_RepoView> {
  final _message = TextEditingController();
  GitOutcome? _outcome;
  Timer? _outcomeTimer;

  @override
  void dispose() {
    _message.dispose();
    _outcomeTimer?.cancel();
    super.dispose();
  }

  /// Runs a git action here; its result shows in a card above the commit
  /// box. Successes fade after a few seconds, errors stay until dismissed.
  Future<bool> _run(Future<void> Function() action, {String? done}) {
    _report(null);
    return runGit(context, action, repo: repo, done: done, onOutcome: _report);
  }

  void _report(GitOutcome? o) {
    if (!mounted) return;
    _outcomeTimer?.cancel();
    setState(() => _outcome = o);
    if (o != null && !o.isError) _outcomeTimer = Timer(const Duration(seconds: 4), () => _report(null));
  }

  GitRepo get repo => widget.repo;

  void _openDiff(GitChange change, bool staged) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DiffScreen(repo: repo, change: change, staged: staged),
    ));
  }

  Future<void> _discard(GitChange change) async {
    final untracked = change.unstaged == GitChangeKind.untracked;
    final ok = await confirmAction(context,
        title: 'Discard changes to “${change.path.split('/').last}”?',
        message: untracked
            ? 'The new file will be deleted. This can\'t be undone.'
            : 'Your edits since the last commit will be lost. This can\'t be undone.',
        action: 'Discard',
        danger: true);
    if (ok && mounted) await _run(() => repo.discard([change]));
  }

  void _rowActions(GitChange change, bool staged) {
    final s = context.services;
    final dir = change.path.contains('/') ? change.path.substring(0, change.path.lastIndexOf('/')) : '';
    showActionSheet(context, title: change.path, actions: [
      SheetAction(Icons.difference_outlined, 'Show changes', () => _openDiff(change, staged)),
      SheetAction(staged ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
          staged ? 'Unstage' : 'Stage', () => _toggle(change, staged)),
      SheetAction(Icons.folder_open_rounded, 'Show in Files',
          () => s.navigation.showFolder(dir.isEmpty ? repo.path : '${repo.path}/$dir')),
      if (!staged) ...[
        null,
        SheetAction(Icons.undo_rounded, 'Discard changes', () => _discard(change), danger: true),
      ],
    ]);
  }

  Future<void> _toggle(GitChange change, bool staged) =>
      _run(() => staged ? repo.unstage([change.path]) : repo.stage([change.path]));

  Future<void> _commit({required bool push}) async {
    final message = _message.text.trim();
    final status = repo.status;
    if (message.isEmpty || status == null) return;
    FocusScope.of(context).unfocus();
    // Nothing staged: commit everything, as "Commit all" says.
    if (status.staged.isEmpty) {
      if (!await _run(() => repo.stage([for (final c in status.unstaged) c.path]))) return;
      if (!mounted) return;
    }
    final committed = await _run(() => repo.commit(message), done: push ? null : 'Committed');
    if (!committed || !mounted) return;
    _message.clear();
    setState(() {});
    if (push) await _run(repo.push, done: 'Committed and pushed');
  }

  Future<void> _sync() async {
    final s = repo.status;
    if (s == null) return;
    if (repo.remotes?.isEmpty ?? true) return publishToGitHub(context, repo);
    if (s.upstream == null) {
      await _run(repo.push, done: 'Branch published');
    } else if (s.behind > 0) {
      if (await _run(repo.pull) && s.ahead > 0 && mounted) {
        await _run(repo.push, done: 'Synced');
      }
    } else if (s.ahead > 0) {
      await _run(repo.push, done: 'Pushed');
    } else {
      await _run(repo.fetch);
      if (mounted && (repo.status?.behind ?? 0) == 0) _report(const GitOutcome('Up to date'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final s = repo.status;
        if (s == null) return const SizedBox.expand();
        final staged = s.staged, unstaged = s.unstaged;
        return Column(
          children: [
            // Only mounted while busy: an indeterminate bar animates (and
            // costs frames) even when transparent.
            SizedBox(
              height: 2,
              child: AnimatedSwitcher(
                duration: Motion.quick,
                child: repo.busy ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink(),
              ),
            ),
            _RepoBar(repo: repo, status: s, onSync: _sync),
            Expanded(
              child: RefreshIndicator(
                color: c.accent,
                backgroundColor: c.surface,
                onRefresh: () async {
                  if (repo.remotes?.isNotEmpty ?? false) {
                    await repo.fetch().catchError((_) {});
                  } else {
                    await repo.refresh();
                  }
                },
                child: s.isClean
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [_Clean(status: s)],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          if (staged.isNotEmpty) ...[
                            _GroupHeader(
                              label: 'Staged',
                              count: staged.length,
                              action: 'Unstage all',
                              onAction: () => _run(() => repo.unstage([for (final c in staged) c.path])),
                            ),
                            for (final change in staged)
                              _ChangeRow(
                                change: change,
                                staged: true,
                                onTap: () => _openDiff(change, true),
                                onToggle: () => _toggle(change, true),
                                onMenu: () => _rowActions(change, true),
                              ),
                          ],
                          if (unstaged.isNotEmpty) ...[
                            _GroupHeader(
                              label: 'Changes',
                              count: unstaged.length,
                              action: 'Stage all',
                              onAction: () => _run(() => repo.stage([for (final c in unstaged) c.path])),
                            ),
                            for (final change in unstaged)
                              _ChangeRow(
                                change: change,
                                staged: false,
                                onTap: () => _openDiff(change, false),
                                onToggle: () => _toggle(change, false),
                                onMenu: () => _rowActions(change, false),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
            AnimatedSize(
              duration: Motion.standard,
              curve: Motion.move,
              alignment: Alignment.bottomCenter,
              child: switch (_outcome) {
                final o? => _OutcomeCard(outcome: o, onDismiss: () => _report(null)),
                null => const SizedBox(width: double.infinity),
              },
            ),
            if (!s.isClean) _CommitBar(controller: _message, repo: repo, status: s, onCommit: _commit),
          ],
        );
      },
    );
  }
}

class _RepoBar extends StatelessWidget {
  const _RepoBar({required this.repo, required this.status, required this.onSync});

  final GitRepo repo;
  final GitStatus status;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    final noRemote = repo.remotes?.isEmpty ?? false;
    final (IconData icon, String label) = switch (s) {
      _ when noRemote => (Icons.cloud_upload_outlined, 'Publish'),
      GitStatus(upstream: null) => (Icons.cloud_upload_outlined, 'Publish branch'),
      GitStatus(:final ahead, :final behind) when ahead > 0 && behind > 0 => (Icons.sync_rounded, '↓$behind ↑$ahead'),
      GitStatus(:final behind) when behind > 0 => (Icons.cloud_download_outlined, 'Pull ↓$behind'),
      GitStatus(:final ahead) when ahead > 0 => (Icons.cloud_upload_outlined, 'Push ↑$ahead'),
      _ => (Icons.sync_rounded, 'Sync'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                tooltip: 'Branches',
                avatar: Icon(Icons.call_split_rounded, size: 16, color: c.accent),
                label: Text(s.branch ?? 'detached', overflow: TextOverflow.ellipsis, style: codeStyle(c.text)),
                onPressed: () => showBranchSheet(context, repo),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: repo.busy ? null : onSync,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        ],
      ),
    );
  }
}

class _Clean extends StatelessWidget {
  const _Clean({required this.status});
  final GitStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = status.lastCommit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 100, 28, 28),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 40, color: c.accent),
          const SizedBox(height: 12),
          Text('No changes', style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            last == null
                ? 'Edit files, or ask an agent to. Changes show up here to review and commit.'
                : 'Last commit: ${last.subject}\n${last.author} · ${timeAgo(last.time)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count, required this.action, required this.onAction});

  final String label, action;
  final int count;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(
        children: [
          Text('$label · $count', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.textMuted)),
          const Spacer(),
          TextButton(
            onPressed: onAction,
            child: Text(action, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// M, A, D… with a colour: added green, deleted red, the rest neutral.
(String, Color) changeBadge(GitChangeKind kind, AppColors c) => switch (kind) {
      GitChangeKind.added => ('A', c.accent),
      GitChangeKind.untracked => ('U', c.accent),
      GitChangeKind.deleted => ('D', c.danger),
      GitChangeKind.renamed => ('R', c.text),
      GitChangeKind.copied => ('C', c.text),
      GitChangeKind.typeChanged => ('T', c.text),
      GitChangeKind.conflicted => ('!', c.danger),
      GitChangeKind.modified => ('M', c.text),
    };

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.staged, required this.onTap, required this.onToggle, required this.onMenu});

  final GitChange change;
  final bool staged;
  final VoidCallback onTap, onToggle, onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = (staged ? change.staged : change.unstaged)!;
    final (letter, color) = changeBadge(kind, c);
    final slash = change.path.lastIndexOf('/');
    final name = change.path.substring(slash + 1);
    final dir = slash < 0 ? null : change.path.substring(0, slash);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
        child: Row(
          children: [
            Semantics(
              label: '${staged ? 'Unstage' : 'Stage'} ${change.path}',
              child: Checkbox(value: staged, onChanged: (_) => onToggle()),
            ),
            SizedBox(
              width: 18,
              child: Text(letter, style: codeStyle(color, size: 12, weight: FontWeight.w600)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeStyle(c.text, size: 14).copyWith(
                        decoration: kind == GitChangeKind.deleted ? TextDecoration.lineThrough : null,
                      )),
                  if (dir != null || change.origPath != null)
                    Text(change.origPath != null ? 'from ${change.origPath}' : dir!,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: codeStyle(c.textMuted, size: 12)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actions',
              icon: Icon(Icons.more_vert_rounded, size: 18, color: c.textMuted),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// A git result kept on screen: "Pushed", or what went wrong and the next
/// step.
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome, required this.onDismiss});

  final GitOutcome outcome;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = outcome.isError ? c.danger : c.accent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(outcome.isError ? Icons.error_outline_rounded : Icons.check_circle_rounded, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(child: Text(outcome.message, style: TextStyle(color: c.text, fontSize: 13, height: 1.35))),
          if (outcome.action case final action?) TextButton(onPressed: outcome.onAction, child: Text(action)),
          IconButton(
            tooltip: 'Dismiss',
            icon: Icon(Icons.close_rounded, size: 16, color: c.textMuted),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _CommitBar extends StatelessWidget {
  const _CommitBar({required this.controller, required this.repo, required this.status, required this.onCommit});

  final TextEditingController controller;
  final GitRepo repo;
  final GitStatus status;
  final Future<void> Function({required bool push}) onCommit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = status.staged.isEmpty;
    final canPush = repo.remotes?.isNotEmpty ?? false;
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border, width: 0.5))),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final ready = controller.text.trim().isNotEmpty && !repo.busy;
              return Column(
                children: [
                  TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: all ? 'Message for all ${plural(status.unstaged.length, 'change')}' : 'Commit message',
                      isDense: true,
                      suffixIcon: TextButton.icon(
                        onPressed: () {
                          controller.text = suggestCommitMessage(status.changes);
                          controller.selection = TextSelection.collapsed(offset: controller.text.length);
                        },
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                        label: const Text('Suggest'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (canPush)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: ready ? () => onCommit(push: true) : null,
                            child: Text(all ? 'Commit all & push' : 'Commit & push'),
                          ),
                        ),
                      if (canPush) const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: ready ? () => onCommit(push: false) : null,
                          child: Text(all ? 'Commit all' : 'Commit'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
