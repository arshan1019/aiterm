import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/agents/agent_installer.dart';
import 'package:aiterm/app/app.dart';
import 'package:aiterm/app/navigation.dart';
import 'package:aiterm/app/services.dart';
import 'package:aiterm/git/git_registry.dart';
import 'package:aiterm/git/git_runner.dart';
import 'package:aiterm/git/git_tools.dart';
import 'package:aiterm/onboarding/setup_pipeline.dart';

// Renders the main screens at phone size with the app's fonts, for layout
// review: `flutter test --update-goldens test_screens/` writes PNGs to
// test_screens/shots/ (CI: .github/workflows/screenshots.yml).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    Future<ByteData> bytes(String path) async => ByteData.sublistView(File(path).readAsBytesSync());
    await (FontLoader('IBMPlexSans')
          ..addFont(bytes('assets/fonts/IBMPlexSans-Regular.ttf'))
          ..addFont(bytes('assets/fonts/IBMPlexSans-Medium.ttf'))
          ..addFont(bytes('assets/fonts/IBMPlexSans-SemiBold.ttf')))
        .load();
    await (FontLoader('JetBrainsMono')
          ..addFont(bytes('assets/fonts/JetBrainsMono-Regular.ttf'))
          ..addFont(bytes('assets/fonts/JetBrainsMono-Bold.ttf')))
        .load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
    await (FontLoader('MaterialIcons')
          ..addFont(bytes('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiterm_shots');
    messenger.setMockMethodCallHandler(const MethodChannel('aiterm/env'), (call) async {
      if (call.method == 'paths') {
        return {'nativeLibDir': '${dir.path}/lib', 'filesDir': dir.path, 'cacheDir': dir.path, 'uptimeMs': '1000'};
      }
      return null;
    });
    var nextId = 1;
    messenger.setMockMethodCallHandler(const MethodChannel('aiterm/pty'), (call) async {
      if (call.method == 'start') return {'id': nextId++};
      return null;
    });
    messenger.setMockStreamHandler(
      const EventChannel('aiterm/pty/output'),
      MockStreamHandler.inline(onListen: (args, sink) {
        sink.success([1, Uint8List.fromList('localhost:~/app# '.codeUnits)]);
      }),
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
  }

  /// Linux installed, Claude Code installed, git ready, with [projects].
  Future<AppServices> boot(WidgetTester tester, {bool linux = true, bool projects = true, bool agent = true}) async {
    phone(tester);
    if (linux) {
      Directory('${dir.path}/alpine/root/app/lib').createSync(recursive: true);
      File('${dir.path}/alpine/root/app/README.md').writeAsStringSync('# Weather');
      File('${dir.path}/alpine/root/app/package.json').writeAsStringSync('{}');
      File('${dir.path}/alpine/root/app/lib/app.dart').writeAsStringSync('void main() {}');
      File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    }
    if (projects) {
      final now = DateTime.now().millisecondsSinceEpoch;
      File('${dir.path}/projects.json').writeAsStringSync(jsonEncode([
        {'id': '1', 'name': 'Weather app', 'path': '/root/app', 'created': now, 'opened': now, 'agent': 'claude'},
        {'id': '2', 'name': 'Portfolio site', 'path': '/root/site', 'created': now, 'opened': now - 7200000},
        {'id': '3', 'name': 'dotfiles', 'path': '/root/dotfiles', 'created': now, 'opened': now - 86400000 * 3},
      ]));
    }
    final s = (await tester.runAsync(AppServices.load))!;
    s.gitTools = GitTools(run: (script, onLine) async => 0);
    await tester.runAsync(s.gitTools.refresh);
    s.git = GitRegistry(_FakeGit());
    s.agents = AgentInstaller(
      run: (script, onOutput) async {
        if (agent && script.contains('command -v')) onOutput('claude');
        return 0;
      },
      launch: (a, title, commands, cwd) {},
    );
    await tester.runAsync(s.agents.refresh);
    await tester.pumpWidget(AiTermApp(services: s));
    await settle(tester);
    return s;
  }

  testWidgets('setup', (tester) async {
    final s = await boot(tester, linux: false, projects: false, agent: false);
    await shot(tester, '01-setup');
    final hold = <String, Future<String?>>{};
    s.setup = SetupPipeline(
      installLinux: (p) async => p('Downloading Alpine Linux', 0.6),
      linuxReady: () => false,
      installTools: () async => null,
      installAgent: (id) => hold.putIfAbsent(id, () => Future<String?>.delayed(const Duration(days: 1))),
      agentName: (id) => AgentInstaller.recipe(id).name,
    );
    await tester.pumpWidget(AiTermApp(services: s));
    s.setup.start(['claude', 'codex']).ignore();
    await settle(tester);
    await shot(tester, '02-setup-progress');
  });

  testWidgets('projects', (tester) async {
    await boot(tester, projects: false);
    await shot(tester, '03-projects-empty');
  });

  testWidgets('projects list and new project', (tester) async {
    await boot(tester);
    await shot(tester, '04-projects');
    await tester.tap(find.byTooltip('Project actions').first);
    await settle(tester);
    await shot(tester, '24-project-actions');
    await tester.tapAt(const Offset(200, 100));
    await settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await shot(tester, '05-add-project-sheet');
    await tester.tap(find.text('Clone repository'));
    await settle(tester);
    await shot(tester, '06-new-project-clone');
  });

  testWidgets('workspace', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.text('Weather app'));
    await settle(tester);
    await shot(tester, '07-workspace-agent');
    s.navigation.openWorkspaceTab(WorkspaceTab.changes);
    await settle(tester);
    await shot(tester, '08-workspace-changes');
    await tester.tap(find.text('README.md'));
    await settle(tester);
    await shot(tester, '09-diff');
    await tester.pageBack();
    await settle(tester);
    s.navigation.openWorkspaceTab(WorkspaceTab.files);
    await settle(tester);
    await shot(tester, '10-workspace-files');
    s.navigation.openWorkspaceTab(WorkspaceTab.preview);
    await settle(tester);
    await shot(tester, '11-workspace-preview-empty');
    s.navigation.openWorkspaceTab(WorkspaceTab.agent);
    s.tabs.open(cwd: '/root/app', project: '/root/app', title: 'Claude Code', agent: 'claude');
    await settle(tester);
    s.tabs.activeIn('/root/app')!.terminal.write('\r\n\x1b[1m✻ Welcome to Claude Code\x1b[0m\r\n\r\n> add a 5-day forecast view\r\n\r\n● Reading lib/app.dart\r\n● Editing lib/forecast.dart\r\n');
    await settle(tester);
    await shot(tester, '12-workspace-session');
  });

  testWidgets('branches', (tester) async {
    final s = await boot(tester);
    await tester.tap(find.text('Weather app'));
    await settle(tester);
    s.navigation.openWorkspaceTab(WorkspaceTab.changes);
    await settle(tester);
    await tester.tap(find.text('main').last);
    await settle(tester);
    await shot(tester, '13-branches');
  });

  testWidgets('identity dialog', (tester) async {
    final s = await boot(tester);
    s.navigation.open(AppTab.settings);
    await settle(tester);
    await shot(tester, '14-settings');
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await settle(tester);
    await shot(tester, '15-settings-scrolled');
    await tester.ensureVisible(find.text('Commit name & email'));
    await tester.tap(find.text('Commit name & email'));
    await settle(tester);
    await shot(tester, '16-identity-dialog');
  });

  testWidgets('terminal, files, agents', (tester) async {
    final s = await boot(tester);
    s.navigation.open(AppTab.terminal);
    await settle(tester);
    s.tabs.activeIn(null)!.terminal.write('\r\nlocalhost:~# ls\r\napp  dotfiles  site\r\nlocalhost:~# ');
    await settle(tester);
    await shot(tester, '17-terminal');
    s.navigation.open(AppTab.files);
    await settle(tester);
    await shot(tester, '18-files');
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await settle(tester);
    await shot(tester, '22-files-add-menu');
    await tester.tapAt(const Offset(20, 300));
    await settle(tester);
    await tester.tap(find.text('Phone'));
    await settle(tester);
    await shot(tester, '23-phone-choose');
    s.navigation.open(AppTab.projects);
    await settle(tester);
    await tester.tap(find.text('Agents'));
    await settle(tester);
    await shot(tester, '19-agents');
  });

  testWidgets('large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final s = await boot(tester);
    await shot(tester, '25-large-projects');
    await tester.tap(find.text('Weather app'));
    await settle(tester);
    s.navigation.openWorkspaceTab(WorkspaceTab.changes);
    await settle(tester);
    await shot(tester, '26-large-changes');
    s.navigation.open(AppTab.settings);
    await settle(tester);
    await shot(tester, '27-large-settings');
  });

  testWidgets('light theme', (tester) async {
    final s = await boot(tester);
    s.settings.dark = false;
    await settle(tester);
    await shot(tester, '20-projects-light');
    await tester.tap(find.text('Weather app'));
    await settle(tester);
    s.navigation.openWorkspaceTab(WorkspaceTab.changes);
    await settle(tester);
    await shot(tester, '21-changes-light');
  });
}

class _FakeGit implements GitRunner {
  @override
  Future<GitResult> run(String folder, List<String> args, {String? stdin}) async {
    return switch (args.first) {
      'rev-parse' => folder.endsWith('app') ? GitResult(0, '$folder\n', '') : const GitResult(128, '', 'fatal: not a git repository'),
      'status' => const GitResult(
          0,
          '# branch.oid abc\x00# branch.head main\x00# branch.upstream origin/main\x00# branch.ab +1 -0\x00'
          '1 .M N... 100644 100644 100644 aaa bbb README.md\x00'
          '1 M. N... 100644 100644 100644 aaa bbb lib/app.dart\x00'
          '1 .D N... 100644 100644 000000 aaa bbb src/old_widget.js\x00'
          '? lib/forecast.dart\x00',
          ''),
      'log' => GitResult(0, 'abc\x00Add city search\x00Sam\x00${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600}\n', ''),
      'remote' => const GitResult(0, 'origin\n', ''),
      'diff' => const GitResult(
          0,
          'diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1,3 +1,5 @@\n # Weather\n-A weather app.\n+A weather app for your phone.\n+\n+Shows a 5-day forecast.\n \n Run with npm start.\n',
          ''),
      'for-each-ref' => const GitResult(0,
          'refs/heads/main\x00*\x00origin/main\nrefs/heads/forecast\x00 \x00\nrefs/remotes/origin/main\x00 \x00\nrefs/remotes/origin/dark-mode\x00 \x00\n', ''),
      _ => const GitResult(0, '', ''),
    };
  }
}
