import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../git/git_actions.dart';
import '../git/git_repo.dart';
import '../git/github_auth.dart';
import '../shared/action_sheet.dart';
import '../shared/folder_picker.dart';
import '../shared/format.dart';
import 'project.dart';
import 'project_service.dart';
import 'project_store.dart';
import 'templates.dart';

/// Where new projects go unless the user picks another folder.
const projectsFolder = '/root/projects';

enum NewProjectKind { empty, template, clone }

/// "New project": empty, from a template, clone, or an existing folder.
void showNewProject(BuildContext context) {
  void push(NewProjectKind kind) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NewProjectScreen(kind: kind),
      ));
  showActionSheet(context, title: 'New project', actions: [
    SheetAction(Icons.create_new_folder_outlined, 'Empty project', () => push(NewProjectKind.empty), accent: true),
    SheetAction(Icons.dashboard_customize_outlined, 'From a template', () => push(NewProjectKind.template)),
    SheetAction(Icons.cloud_download_outlined, 'Clone a repository', () => push(NewProjectKind.clone)),
    null,
    SheetAction(Icons.folder_open_rounded, 'Open a folder in Linux', () => openFolderAsProject(context)),
  ]);
}

Future<void> openFolderAsProject(BuildContext context) async {
  final s = context.services;
  final path = await pickLinuxFolder(context, title: 'Open a folder', action: 'Open');
  if (path == null || !context.mounted) return;
  s.showProject(await s.projectService.openExisting(path));
}

class NewProjectScreen extends StatefulWidget {
  const NewProjectScreen({super.key, required this.kind});

  final NewProjectKind kind;

  @override
  State<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends State<NewProjectScreen> {
  late final _s = context.services;
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _parent = projectsFolder;
  ProjectTemplate _template = projectTemplates.first;
  bool _busy = false;
  String? _error;

  List<GitHubRepo>? _repos;
  String? _reposError;
  String _filter = '';

  bool get _clone => widget.kind == NewProjectKind.clone;

  String get _folderName => _clone ? repoNameFor(_url.text) : folderNameFor(_name.text);

  String get _path => '$_parent/${_folderName.isEmpty ? '…' : _folderName}';

  bool get _ready => !_busy && (_clone ? repoNameFor(_url.text).isNotEmpty : _name.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _url.addListener(_changed);
    if (_clone && _s.github.user != null) _loadRepos();
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _error = null);

  Future<void> _loadRepos() async {
    try {
      final repos = await _s.github.repositories();
      if (mounted) setState(() => _repos = repos);
    } catch (e) {
      if (mounted) setState(() => _reposError = '$e');
    }
  }

  Future<void> _signIn() async {
    if (await signInToGitHub(context)) _loadRepos();
    if (mounted) setState(() {});
  }

  Future<void> _pickParent() async {
    final picked = await pickLinuxFolder(context, title: 'Create in', start: _parent, action: 'Use');
    if (picked != null) setState(() => _parent = picked);
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    if (!await ensureGitTools(context) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = _s.projectService;
    try {
      final Project p = switch (widget.kind) {
        NewProjectKind.empty => await svc.createEmpty(name: _name.text.trim(), path: _path),
        NewProjectKind.template => await svc.createFromTemplate(_template, name: _name.text.trim(), path: _path),
        NewProjectKind.clone => await svc.clone(_url.text.trim(), path: _path),
      };
      // The form gives way to the new project (back goes to Projects).
      _s.showProject(p);
    } on GitError catch (e) {
      if (e.kind == GitErrorKind.auth && mounted && await signInToGitHub(context) && mounted) {
        setState(() => _busy = false);
        return _create();
      }
      _fail(e.message);
    } on FolderNotEmpty catch (e) {
      _fail('$e');
    } on ProjectExists catch (e) {
      _fail('$e');
    } catch (e) {
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = switch (widget.kind) {
      NewProjectKind.empty => 'Empty project',
      NewProjectKind.template => 'From a template',
      NewProjectKind.clone => 'Clone a repository',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (widget.kind == NewProjectKind.template) ...[
                  _label(context, 'Template'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in projectTemplates)
                        ChoiceChip(
                          label: Text(t.name),
                          selected: t == _template,
                          onSelected: (_) => setState(() => _template = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_template.description, style: TextStyle(color: c.textMuted, fontSize: 12)),
                  const SizedBox(height: 20),
                ],
                if (_clone) ...[
                  _label(context, 'Repository'),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'https://github.com/owner/repo'),
                  ),
                ] else ...[
                  _label(context, 'Name'),
                  TextField(
                    controller: _name,
                    autofocus: widget.kind == NewProjectKind.empty,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'e.g. Weather app'),
                    onSubmitted: (_) => _ready ? _create() : null,
                  ),
                ],
                const SizedBox(height: 20),
                _label(context, 'Folder in Linux'),
                Row(
                  children: [
                    Expanded(
                      child: Text(shortPath(_path), style: TextStyle(color: c.text, fontSize: 13)),
                    ),
                    TextButton(onPressed: _busy ? null : _pickParent, child: const Text('Change')),
                  ],
                ),
                if (_error case final e?) ...[
                  const SizedBox(height: 8),
                  Text(e, style: TextStyle(color: c.danger, fontSize: 13, height: 1.4)),
                ],
                if (_clone) ...[
                  const SizedBox(height: 20),
                  _repoList(context),
                ],
              ],
            ),
          ),
          Material(
            color: c.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _ready ? _create : null,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_clone ? 'Clone' : 'Create project'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: context.colors.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
      );

  Widget _repoList(BuildContext context) {
    final c = context.colors;
    if (_s.github.user == null) {
      return OutlinedButton.icon(
        onPressed: _signIn,
        icon: const Icon(Icons.login_rounded, size: 18),
        label: const Text('Sign in to GitHub to pick from your repositories'),
      );
    }
    if (_reposError case final e?) return Text(e, style: TextStyle(color: c.danger, fontSize: 12));
    final repos = _repos;
    if (repos == null) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
    final shown = [for (final r in repos) if (r.fullName.toLowerCase().contains(_filter)) r];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'Your repositories'),
        if (repos.length > 8)
          TextField(
            decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search_rounded, size: 18), isDense: true),
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          ),
        for (final r in shown.take(50))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(r.private ? Icons.lock_outline_rounded : Icons.book_outlined, size: 18, color: c.textMuted),
            title: Text(r.fullName, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              [?r.description, timeAgo(r.updatedAt)].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
            selected: _url.text == r.cloneUrl,
            onTap: () => _url.text = r.cloneUrl,
          ),
        if (shown.isEmpty) Text('No matches', style: TextStyle(color: c.textMuted, fontSize: 12)),
      ],
    );
  }
}
