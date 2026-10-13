import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/git_parsers.dart';
import 'package:aiterm/git/git_repo.dart';
import 'package:aiterm/git/git_runner.dart';
import 'package:aiterm/linux/system_gitconfig.dart';

/// The git engine against real git in temp repos (git is in the dev
/// sandbox and on CI); a bare repo stands in for GitHub.
void main() {
  late Directory tmp;
  late ProcessGitRunner git;
  late String home;

  Future<GitResult> sh(String repo, List<String> args) => git.run(repo, args);
  Future<Object?> errorOf(Future<void> f) async {
    try {
      await f;
      return null;
    } catch (e) {
      return e;
    }
  }
  void write(String path, String text) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<String> newRepo(String name, {bool commit = true}) async {
    final path = '${tmp.path}/$name';
    Directory(path).createSync(recursive: true);
    await sh(path, ['init', '-q', '-b', 'main']);
    if (commit) {
      write('$path/README.md', '# $name\n');
      await sh(path, ['add', '-A']);
      await sh(path, ['commit', '-qm', 'Initial']);
    }
    return path;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aiterm_git');
    home = '${tmp.path}/home';
    Directory(home).createSync();
    // proot here emulates hard links as symlinks, as it does in the app.
    File('$home/.gitconfig').writeAsStringSync(
        '[user]\n\tname = Test\n\temail = test@example.com\n[init]\n\tdefaultBranch = main\n[core]\n\tcreateObject = rename\n');
    git = ProcessGitRunner(env: {'HOME': home, 'GIT_CONFIG_NOSYSTEM': '1'});
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('status', () {
    test('every kind of change, including spaces and renames', () async {
      final r = await newRepo('a');
      write('$r/src/main.dart', 'void main() {}\n');
      write('$r/old name.txt', 'x\n');
      await sh(r, ['add', '-A']);
      await sh(r, ['commit', '-qm', 'files']);
      write('$r/README.md', '# changed\n'); // modified, unstaged
      write('$r/new file.txt', 'n\n'); // untracked
      await sh(r, ['mv', 'old name.txt', 'renamed.txt']); // renamed, staged
      File('$r/src/main.dart').deleteSync(); // deleted, unstaged

      final repo = GitRepo(r, git);
      await repo.refresh();
      final s = repo.status!;
      expect(s.branch, 'main');
      final byPath = {for (final c in s.changes) c.path: c};
      expect(byPath['README.md']!.unstaged, GitChangeKind.modified);
      expect(byPath['README.md']!.staged, isNull);
      expect(byPath['new file.txt']!.unstaged, GitChangeKind.untracked);
      expect(byPath['renamed.txt']!.staged, GitChangeKind.renamed);
      expect(byPath['renamed.txt']!.origPath, 'old name.txt');
      expect(byPath['src/main.dart']!.unstaged, GitChangeKind.deleted);
      expect(s.staged.map((c) => c.path), ['renamed.txt']);
      expect(s.unstaged.map((c) => c.path).toSet(), {'README.md', 'new file.txt', 'src/main.dart'});
    });

    test('a clean repo, and a repo with no commits yet', () async {
      final clean = GitRepo(await newRepo('clean'), git);
      await clean.refresh();
      expect(clean.status!.changes, isEmpty);
      expect(clean.status!.isClean, isTrue);

      final fresh = GitRepo(await newRepo('fresh', commit: false), git);
      write('${fresh.path}/a.txt', 'a');
      await fresh.refresh();
      expect(fresh.status!.branch, 'main');
      expect(fresh.status!.hasCommits, isFalse);
      expect(fresh.status!.unstaged.single.path, 'a.txt');
    });
  });

  group('stage, unstage, discard, commit', () {
    test('stage and unstage move files between groups', () async {
      final r = await newRepo('b');
      write('$r/README.md', 'changed\n');
      write('$r/x.txt', 'x\n');
      final repo = GitRepo(r, git);
      await repo.stage(['README.md', 'x.txt']);
      expect(repo.status!.staged.map((c) => c.path).toSet(), {'README.md', 'x.txt'});
      await repo.unstage(['x.txt']);
      expect(repo.status!.staged.map((c) => c.path), ['README.md']);
      expect(repo.status!.unstaged.single.path, 'x.txt');
    });

    test('discard restores tracked files and removes untracked ones', () async {
      final r = await newRepo('c');
      write('$r/README.md', 'oops\n');
      write('$r/junk.txt', 'j\n');
      final repo = GitRepo(r, git);
      await repo.refresh();
      await repo.discard(repo.status!.unstaged);
      expect(File('$r/README.md').readAsStringSync(), '# c\n');
      expect(File('$r/junk.txt').existsSync(), isFalse);
      expect(repo.status!.isClean, isTrue);
    });

    test('commit with staged changes; the last commit is reported', () async {
      final r = await newRepo('d');
      write('$r/f.txt', 'f\n');
      final repo = GitRepo(r, git);
      await repo.stage(['f.txt']);
      await repo.commit('Add f');
      expect(repo.status!.isClean, isTrue);
      expect(repo.status!.lastCommit?.subject, 'Add f');
    });

    test('commit without an identity asks for one', () async {
      File('$home/.gitconfig').writeAsStringSync('[core]\n\tcreateObject = rename\n');
      final r = await newRepo('e', commit: false);
      write('$r/f.txt', 'f\n');
      final repo = GitRepo(r, git);
      await repo.stage(['f.txt']);
      final error = await errorOf(repo.commit('first'));
      expect(error, isA<GitError>().having((e) => e.kind, 'kind', GitErrorKind.identity));
    });
  });

  group('branches', () {
    test('create, switch and list', () async {
      final repo = GitRepo(await newRepo('f'), git);
      await repo.createBranch('feature/x');
      expect(repo.status!.branch, 'feature/x');
      await repo.switchBranch('main');
      expect(repo.status!.branch, 'main');
      final branches = await repo.branches();
      expect(branches.where((b) => !b.remote).map((b) => b.name).toSet(), {'main', 'feature/x'});
      expect(branches.firstWhere((b) => b.current).name, 'main');
    });
  });

  group('sync with a remote', () {
    late String remote;
    setUp(() async {
      remote = '${tmp.path}/remote.git';
      await git.run(tmp.path, ['init', '-q', '--bare', '-b', 'main', remote]);
    });

    test('first push publishes the branch; then ahead/behind are tracked', () async {
      final r = await newRepo('g');
      await sh(r, ['remote', 'add', 'origin', remote]);
      final repo = GitRepo(r, git);
      await repo.push(); // no upstream yet: publishes
      await repo.refresh();
      expect(repo.status!.upstream, 'origin/main');
      expect(repo.status!.ahead, 0);

      write('$r/a.txt', 'a');
      await repo.stage(['a.txt']);
      await repo.commit('a');
      expect(repo.status!.ahead, 1);
      await repo.push();
      expect(repo.status!.ahead, 0);

      // Someone else pushes; we fetch and see we're behind, then pull.
      final other = '${tmp.path}/other';
      await git.run(tmp.path, ['clone', '-q', '--no-hardlinks', remote, other]);
      write('$other/b.txt', 'b');
      await sh(other, ['add', '-A']);
      await sh(other, ['commit', '-qm', 'b']);
      await sh(other, ['push', '-q']);
      await repo.fetch();
      expect(repo.status!.behind, 1);
      await repo.pull();
      expect(repo.status!.behind, 0);
      expect(File('$r/b.txt').existsSync(), isTrue);
    });

    test('a rejected push says to pull first', () async {
      final r = await newRepo('h');
      await sh(r, ['remote', 'add', 'origin', remote]);
      final repo = GitRepo(r, git);
      await repo.push();
      final other = '${tmp.path}/other2';
      await git.run(tmp.path, ['clone', '-q', '--no-hardlinks', remote, other]);
      write('$other/c.txt', 'c');
      await sh(other, ['add', '-A']);
      await sh(other, ['commit', '-qm', 'c']);
      await sh(other, ['push', '-q']);
      write('$r/d.txt', 'd');
      await repo.stage(['d.txt']);
      await repo.commit('d');
      final error = await errorOf(repo.push());
      expect(error, isA<GitError>().having((e) => e.kind, 'kind', GitErrorKind.pullFirst));
    });
  });

  group('diff', () {
    test('modified file: hunks with line numbers', () async {
      final r = await newRepo('i');
      write('$r/a.txt', 'one\ntwo\nthree\n');
      await sh(r, ['add', '-A']);
      await sh(r, ['commit', '-qm', 'a']);
      write('$r/a.txt', 'one\n2\nthree\nfour\n');
      final repo = GitRepo(r, git);
      final d = await repo.diff('a.txt');
      expect(d.hunks, hasLength(1));
      final lines = d.hunks.single.lines;
      expect(lines.where((l) => l.kind == DiffLineKind.removed).single.text, 'two');
      expect(lines.where((l) => l.kind == DiffLineKind.added).map((l) => l.text), ['2', 'four']);
      final four = lines.firstWhere((l) => l.text == 'four');
      expect(four.newLine, 4);
      expect(four.oldLine, isNull);
      expect(d.added, 2);
      expect(d.removed, 1);
    });

    test('untracked file shows as all added', () async {
      final r = await newRepo('j');
      write('$r/new.txt', 'a\nb\n');
      final d = await GitRepo(r, git).diff('new.txt');
      expect(d.added, 2);
      expect(d.removed, 0);
    });
  });

  group('parsers', () {
    test('remote URLs name host, owner and repo', () {
      expect(parseRemote('https://github.com/arshan1019/aiterm.git'), ('github.com', 'arshan1019', 'aiterm'));
      expect(parseRemote('git@github.com:arshan1019/aiterm.git'), ('github.com', 'arshan1019', 'aiterm'));
      expect(parseRemote('ssh://git@gitlab.com/group/proj'), ('gitlab.com', 'group', 'proj'));
      expect(parseRemote('/local/path.git'), isNull);
    });

    test('a binary file in a diff is marked binary', () {
      final d = parseDiff('diff --git a/i.png b/i.png\nindex 1..2 100644\nBinary files a/i.png and b/i.png differ\n');
      expect(d.single.binary, isTrue);
    });
  });

  group('system gitconfig for proot', () {
    test('adds createObject = rename (hard links are emulated)', () {
      final out = withProotGitDefaults('');
      expect(out, contains('[core]'));
      expect(out, contains('createObject = rename'));
    });

    test('keeps existing settings and is idempotent', () {
      const existing = '[core]\n\tautocrlf = input\n[user]\n\tname = Me\n';
      final once = withProotGitDefaults(existing);
      expect(once, contains('autocrlf = input'));
      expect(once, contains('name = Me'));
      expect(withProotGitDefaults(once), once);
    });
  });
}
