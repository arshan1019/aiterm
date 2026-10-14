import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../shared/format.dart';
import 'git_actions.dart';
import 'git_repo.dart';
import 'github_auth.dart';

/// Signs in to GitHub if needed, then lists the account's repositories.
Future<void> openGitHubRepos(BuildContext context) async {
  final s = context.services;
  if (s.github.user == null && !await signInToGitHub(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GitHubReposScreen()));
}

/// The signed-in account's repositories: tap one to work on it. It's
/// cloned into ~/projects and opened; one already there just opens.
class GitHubReposScreen extends StatefulWidget {
  const GitHubReposScreen({super.key});

  @override
  State<GitHubReposScreen> createState() => _GitHubReposScreenState();
}

class _GitHubReposScreenState extends State<GitHubReposScreen> {
  late final _s = context.services;
  List<GitHubRepo>? _repos;
  String? _error;
  String _filter = '';
  String? _cloning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repos = await _s.github.repositories();
      if (mounted) setState(() => _repos = repos);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Opens [repo]'s project, cloning it the first time (ProjectService
  /// decides where; the screen only shows progress and errors).
  Future<void> _open(GitHubRepo repo) async {
    if (_cloning != null) return;
    if (!await ensureGitTools(context) || !mounted) return;
    setState(() => _cloning = repo.fullName);
    try {
      _s.showProject(await _s.projectService.addRepository(repo.cloneUrl, name: repo.name));
    } on GitError catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _cloning = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repos = _repos;
    final shown = repos == null ? const <GitHubRepo>[] : [for (final r in repos) if (r.fullName.toLowerCase().contains(_filter)) r];
    return Scaffold(
      appBar: AppBar(title: Text(_s.github.user?.login ?? 'GitHub')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search repositories', prefixIcon: Icon(Icons.search_rounded, size: 20)),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(height: 2, child: _cloning != null || (repos == null && _error == null) ? const LinearProgressIndicator(minHeight: 2) : null),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 13)),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: c.accent,
                    backgroundColor: c.surface,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final r = shown[i];
                        final added = _s.projectService.repositoryProject(r.name) != null;
                        return ListTile(
                          enabled: _cloning == null || _cloning == r.fullName,
                          leading: Icon(r.private ? Icons.lock_outline_rounded : Icons.book_outlined, size: 20),
                          title: Text(r.fullName, style: codeStyle(c.text, size: 14)),
                          subtitle: Text(
                            [?r.description, timeAgo(r.updatedAt)].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textMuted, fontSize: 12),
                          ),
                          trailing: _cloning == r.fullName
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(added ? 'Open' : 'Clone', style: TextStyle(color: c.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                          onTap: () => _open(r),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
