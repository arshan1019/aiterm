import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/git/git_runner.dart';
import 'package:aiterm/git/git_tools.dart';
import 'package:aiterm/projects/project.dart';
import 'package:aiterm/projects/project_service.dart';
import 'package:aiterm/projects/project_store.dart';
import 'package:aiterm/projects/templates.dart';

void main() {
  late Directory tmp;
  late ProcessGitRunner git;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aiterm_proj');
    File('${tmp.path}/.gitconfig')
        .writeAsStringSync('[user]\n\tname = T\n\temail = t@e\n[init]\n\tdefaultBranch = main\n[core]\n\tcreateObject = rename\n');
    git = ProcessGitRunner(env: {'HOME': tmp.path, 'GIT_CONFIG_NOSYSTEM': '1'});
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProjectService service(ProjectStore store) => ProjectService(store: store, git: git, hostPath: (p) => p);

  test('projects on phone storage are recognised (Linux sees it at /sdcard)', () {
    expect(onPhoneStorage('/sdcard/Projects/site'), isTrue);
    expect(onPhoneStorage('/storage/emulated/0/x'), isTrue);
    expect(onPhoneStorage('/root/projects/site'), isFalse);
    expect(onPhoneStorage('/sdcardish'), isFalse);
  });

  group('store', () {
    test('an agent opened in a folder makes it a recent project and is remembered', () async {
      final file = '${tmp.path}/projects.json';
      final store = ProjectStore(file);
      await store.load();
      await store.add(name: 'old', path: '/root/old');
      final p = await store.usedAgent('/root/notes', 'claude');
      expect(p!.name, 'notes');
      expect(p.agentId, 'claude');
      expect(store.projects.first.path, '/root/notes'); // most recent first
      await store.usedAgent('/root/old', 'codex');
      final again = ProjectStore(file);
      await again.load();
      expect(again.byPath('/root/old')!.agentId, 'codex');
      expect(again.projects.first.path, '/root/old');
      expect(again.projects, hasLength(2));
    });

    test('home and / are not projects', () async {
      final store = ProjectStore('${tmp.path}/projects.json');
      await store.load();
      expect(await store.usedAgent('/root', 'claude'), isNull);
      expect(await store.usedAgent('/', 'claude'), isNull);
      expect(store.projects, isEmpty);
    });

    test('projects persist, newest-opened first, one per folder', () async {
      final file = '${tmp.path}/projects.json';
      final store = ProjectStore(file);
      await store.load();
      final a = await store.add(name: 'a', path: '/root/a');
      await store.add(name: 'b', path: '/root/b');
      expect(store.add(name: 'dup', path: '/root/a'), throwsA(isA<ProjectExists>()));
      await store.opened(a);
      final again = ProjectStore(file);
      await again.load();
      expect(again.projects.map((p) => p.name), ['a', 'b']);
      await again.rename(again.projects.first, 'alpha');
      await again.remove(again.projects.last);
      final third = ProjectStore(file);
      await third.load();
      expect(third.projects.single.name, 'alpha');
    });
  });

  group('create', () {
    late ProjectStore store;
    setUp(() async {
      store = ProjectStore('${tmp.path}/projects.json');
      await store.load();
    });

    test('new empty project: folder made, git initialised, listed', () async {
      final p = await service(store).createEmpty(name: 'hello', path: '${tmp.path}/projects/hello');
      expect(Directory('${tmp.path}/projects/hello/.git').existsSync(), isTrue);
      expect(store.projects.single.id, p.id);
    });

    test('a folder that already has files is not overwritten by "new"', () async {
      Directory('${tmp.path}/busy').createSync();
      File('${tmp.path}/busy/keep.txt').writeAsStringSync('k');
      expect(service(store).createEmpty(name: 'busy', path: '${tmp.path}/busy'), throwsA(isA<FolderNotEmpty>()));
    });

    test('template project gets its starter files and git', () async {
      for (final t in projectTemplates) {
        final path = '${tmp.path}/t-${t.id}';
        await service(store).createFromTemplate(t, name: 'demo ${t.id}', path: path);
        for (final f in t.files.keys) {
          expect(File('$path/$f').existsSync(), isTrue, reason: '${t.id}: $f');
        }
        expect(Directory('$path/.git').existsSync(), isTrue);
      }
      expect(File('${tmp.path}/t-node/package.json').readAsStringSync(), contains('"name": "demo-node"'));
    });

    test('clone (a local repo here) becomes a project', () async {
      final origin = '${tmp.path}/origin';
      Directory(origin).createSync();
      await git.run(origin, ['init', '-q', '-b', 'main']);
      File('$origin/README.md').writeAsStringSync('hi');
      await git.run(origin, ['add', '-A']);
      await git.run(origin, ['commit', '-qm', 'i']);
      final p = await service(store).clone(origin, path: '${tmp.path}/projects/cloned');
      expect(File('${tmp.path}/projects/cloned/README.md').readAsStringSync(), 'hi');
      expect(p.name, 'cloned');
    });

    test('open existing folder; offers git init when it is not a repo', () async {
      Directory('${tmp.path}/plain').createSync();
      final s = service(store);
      final p = await s.openExisting('${tmp.path}/plain');
      expect(await s.isRepo(p.path), isFalse);
      await s.initGit(p);
      expect(await s.isRepo(p.path), isTrue);
    });

    test('names become safe folder names', () {
      expect(folderNameFor('My App!'), 'my-app');
      expect(folderNameFor('  data_viz 2 '), 'data_viz-2');
      expect(repoNameFor('https://github.com/acme/rocket.git'), 'rocket');
      expect(repoNameFor('git@github.com:acme/rocket'), 'rocket');
    });
  });

  group('git tools', () {
    test('installs git, gh and ssh when missing, then reports ready', () async {
      final scripts = <String>[];
      var installed = false;
      final tools = GitTools(run: (script, onLine) async {
        scripts.add(script);
        if (script.contains('command -v')) return installed ? 0 : 1;
        if (script.contains('apk add')) installed = true;
        return 0;
      });
      await tools.refresh();
      expect(tools.status, ToolsStatus.missing);
      await tools.ensure();
      expect(scripts.last, contains('command -v'));
      expect(scripts.firstWhere((s) => s.contains('apk add')), allOf(contains('git'), contains('github-cli'), contains('openssh-client')));
      expect(tools.status, ToolsStatus.ready);
    });
  });
}
