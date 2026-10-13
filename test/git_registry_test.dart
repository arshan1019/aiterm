import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/git_registry.dart';
import 'package:aiterm/git/git_runner.dart';

void main() {
  late Directory tmp;
  late ProcessGitRunner git;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aiterm_reg');
    File('${tmp.path}/.gitconfig').writeAsStringSync('[core]\n\tcreateObject = rename\n');
    git = ProcessGitRunner(env: {'HOME': tmp.path, 'GIT_CONFIG_NOSYSTEM': '1'});
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('finds the repository a folder belongs to, and shares one object per repo', () async {
    final repo = '${tmp.path}/proj';
    Directory('$repo/src/deep').createSync(recursive: true);
    await git.run(repo, ['init', '-q', '-b', 'main']);
    final reg = GitRegistry(git);
    expect(await reg.rootFor('$repo/src/deep'), repo);
    expect(await reg.rootFor(repo), repo);
    expect(await reg.rootFor(tmp.path), isNull);
    final a = await reg.repoFor('$repo/src');
    final b = await reg.repoFor(repo);
    expect(a, isNotNull);
    expect(identical(a, b), isTrue);
    expect(await reg.repoFor(tmp.path), isNull);
  });

  test('a folder that becomes a repo is found after forget()', () async {
    final dir = '${tmp.path}/later';
    Directory(dir).createSync();
    final reg = GitRegistry(git);
    expect(await reg.rootFor(dir), isNull);
    await git.run(dir, ['init', '-q']);
    reg.forget(dir);
    expect(await reg.rootFor(dir), dir);
  });

  test('commit identity: none at first, then set globally', () async {
    final reg = GitRegistry(git);
    expect(await reg.identity(), isNull);
    await reg.setIdentity('Mona Lisa', '42+octocat@users.noreply.github.com');
    expect(await reg.identity(), ('Mona Lisa', '42+octocat@users.noreply.github.com'));
  });

  test('remotes are known after a refresh, and adding one updates them', () async {
    final dir = '${tmp.path}/r';
    Directory(dir).createSync();
    await git.run(dir, ['init', '-q', '-b', 'main']);
    final repo = (await GitRegistry(git).repoFor(dir))!;
    await repo.refresh();
    expect(repo.remotes, isEmpty);
    await repo.addRemote('https://github.com/octocat/r.git');
    expect(repo.remotes, ['origin']);
  });

  test('the shell quoting used for Linux runs survives odd names', () {
    expect(shellQuote("it's a file"), "'it'\\''s a file'");
    expect(gitCommandLine('/root/my app', ['commit', '-m', "fix: user's \$HOME"]),
        "cd '/root/my app' && exec git 'commit' '-m' 'fix: user'\\''s \$HOME'");
  });
}
