import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/app.dart';
import 'package:aiterm/app/navigation.dart';
import 'package:aiterm/app/services.dart';
import 'package:aiterm/git/git_registry.dart';
import 'package:aiterm/git/git_runner.dart';
import 'package:aiterm/git/git_screen.dart';
import 'package:aiterm/git/git_tools.dart';
import 'package:aiterm/terminal/terminal_session.dart';
import 'package:xterm/xterm.dart';

// Widget tests overflow the stack inside the Acode sandbox this project is
// developed in; they run on CI (.github/workflows/test.yml).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aiterm_test');
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
        sink.success([1, Uint8List.fromList('localhost:~# '.codeUnits)]);
      }),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Starts the app; [home] false switches to the terminal tab, which most
  /// tests drive (agents is the home tab).
  Future<AppServices> boot(WidgetTester tester, {bool home = false}) async {
    final services = (await tester.runAsync(AppServices.load))!;
    await tester.pumpWidget(AiTermApp(services: services));
    await tester.pumpAndSettle();
    if (!home) {
      await tester.tap(find.text('terminal'));
      await tester.pumpAndSettle();
    }
    return services;
  }

  // Lets real file IO (listing folders, starting sessions) finish.
  // Real IO resumes in the test's fake zone only on a pump, and listing a
  // folder takes several IO round trips, so alternate a few times.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows the tabs and Linux setup', (tester) async {
    await boot(tester);
    expect(find.text('terminal'), findsOneWidget);
    expect(find.text('files'), findsOneWidget);
    expect(find.text('settings'), findsOneWidget);
    expect(find.text('Set up aiterm'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('walks through every screen without framework errors', (tester) async {
    await boot(tester);

    // Android's shell lives in Settings, out of the way of first-run setup.
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);

    // New terminal tab, switch back, open its menu and close it.
    await tester.tap(find.byTooltip('New tab'));
    await tester.pumpAndSettle();
    expect(find.text('shell 2'), findsOneWidget);
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();

    // Close the unpinned tab via its close button.
    await tester.tap(find.text('shell 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('shell 2'), findsNothing);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('installed Linux: links, selection toolbar, sheets, files', (tester) async {
    Directory('${dir.path}/alpine/root/proj').createSync(recursive: true);
    File('${dir.path}/alpine/root/notes.txt').writeAsStringSync('hello');
    File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    final services = await boot(tester);
    await settleIo(tester);
    final session = services.tabs.active;

    // Tap a URL: the whole URL is selected and the toolbar offers Open.
    // Row 6: clear of the notice that floats over the top rows.
    session.terminal.write('\r\n' * 6 + 'see https://example.com/some/long/path now\r\n');
    await tester.pump();
    Offset cell(int x, int y) {
      final render = tester.state<TerminalViewState>(find.byType(TerminalView).first).renderTerminal;
      return render.localToGlobal(render.getOffset(CellOffset(x, y)) + render.cellSize.center(Offset.zero));
    }
    final url = cell(10, 6);
    await tester.tapAt(url);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);

    // Switching screens with the toolbar up must hide it cleanly.
    await tester.tap(find.text('files'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsNothing);
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();

    // Show the toolbar again, then close the tab underneath it.
    await tester.tapAt(url);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    await tester.tapAt(url);
    await tester.pumpAndSettle();
    services.tabs.close(session);
    await tester.pumpAndSettle();

    // Assistant sheet opens and closes.
    services.tabs.active.state.value = SessionState.running;
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.auto_awesome_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('What do you want to do?'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Files: into a folder and back, then open the text file.
    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.text('proj'));
    await settleIo(tester);
    expect(find.text('Empty folder'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await settleIo(tester);
    await tester.tap(find.text('notes.txt'));
    await settleIo(tester);
    expect(find.text('hello'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Theme switch with everything mounted.
    services.settings.dark = false;
    await tester.pumpAndSettle();
    services.settings.dark = true;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('name dialogs, rename tab, selection handles', (tester) async {
    File('${dir.path}/alpine/.aiterm-installed')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x');
    Directory('${dir.path}/alpine/root').createSync(recursive: true);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    final services = await boot(tester);
    await settleIo(tester);

    // Rename the terminal tab through its menu.
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'build');
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('build'), findsOneWidget);

    // Long-press a word: selection with two handles; drag the end handle.
    final session = services.tabs.active;
    session.terminal.write('\r\n' * 6 + 'hello wonderful world\r\n');
    await tester.pump();
    Offset cell(int x, int y) {
      final render = tester.state<TerminalViewState>(find.byType(TerminalView).first).renderTerminal;
      return render.localToGlobal(render.getOffset(CellOffset(x, y)) + render.cellSize.center(Offset.zero));
    }

    await tester.longPressAt(cell(8, 6));
    await tester.pumpAndSettle();
    expect(session.selection.selection, isNotNull);
    final handles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Handle');
    expect(handles, findsNWidgets(2));
    final before = session.selection.selection!.normalized.end;
    await tester.drag(handles.last, Offset(cell(20, 6).dx - cell(15, 6).dx, 0));
    await tester.pumpAndSettle();
    expect(session.selection.selection!.normalized.end.x, greaterThan(before.x));
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    // Files: new folder via the dialog.
    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'made');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await settleIo(tester);
    expect(find.text('made'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('Files: terminal (and installed agents) from the top menu and each folder\'s menu', (tester) async {
    Directory('${dir.path}/alpine/root/proj').createSync(recursive: true);
    File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    final services = await boot(tester);
    await settleIo(tester);

    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.byTooltip('Folder actions'));
    await tester.pumpAndSettle();
    // No agent is installed here, so none is offered (only installed ones are).
    expect(find.textContaining('Open in '), findsNothing);
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();
    expect(services.navigation.tab.name, 'terminal');
    expect(services.tabs.active.cwd, '/root');

    // Each row has a visible actions button; nothing needs a long-press.
    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Open in '), findsNothing);
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();
    expect(services.tabs.active.cwd, '/root/proj');
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('switching tabs or screens does not pop the keyboard up', (tester) async {
    await boot(tester);
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'not on first show');

    await tester.tap(find.byTooltip('New tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'not on tab switch');

    await tester.tap(find.text('files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('terminal'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'not when returning to the terminal');

    // Tapping the terminal is how the keyboard opens.
    await tester.tap(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'TerminalView').first);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('home is Projects; first launch sets up Linux there', (tester) async {
    await boot(tester, home: true);
    expect(find.text('projects'), findsOneWidget);
    // First launch: one setup screen, agents picked up front.
    expect(find.text('Set up aiterm'), findsOneWidget);
    for (final name in ['Claude Code', 'Gemini CLI', 'Codex CLI']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Set up'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('with Linux set up: empty projects, an agent prompt, the agents page, new project choices', (tester) async {
    File('${dir.path}/alpine/.aiterm-installed')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final services = await boot(tester, home: true);
    expect(services.navigation.tab.name, 'projects');
    expect(find.text('Start a project'), findsOneWidget);
    expect(find.text('Set up an AI agent'), findsOneWidget);

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    for (final name in ['Claude Code', 'Gemini CLI', 'Codex CLI']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Install'), findsNWidgets(3));
    expect(find.textContaining('Sign in the first time'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create your first project'));
    await tester.pumpAndSettle();
    for (final way in ['Empty project', 'From a template', 'Clone a repository', 'Open a folder in Linux']) {
      expect(find.text(way), findsOneWidget);
    }
    await tester.tap(find.text('From a template'));
    await tester.pumpAndSettle();
    expect(find.text('Node.js'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Weather app');
    await tester.pump();
    expect(find.text('~/projects/weather-app'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('a project opens its workspace; changes are reviewed and committed', (tester) async {
    Directory('${dir.path}/alpine/root/app').createSync(recursive: true);
    File('${dir.path}/alpine/root/app/main.dart').writeAsStringSync('void main() {}');
    File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    final now = DateTime.now().millisecondsSinceEpoch;
    File('${dir.path}/projects.json').writeAsStringSync(
        jsonEncode([{'id': '1', 'name': 'Weather app', 'path': '/root/app', 'created': now, 'opened': now}]));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    final services = (await tester.runAsync(AppServices.load))!;
    final git = _FakeGit();
    services.gitTools = GitTools(run: (script, onLine) async => 0);
    await services.gitTools.refresh();
    services.git = GitRegistry(git);
    await tester.pumpWidget(AiTermApp(services: services));
    await settleIo(tester);

    expect(find.text('Weather app'), findsOneWidget);
    expect(find.text('2 changes'), findsOneWidget); // on the card
    await tester.tap(find.text('Weather app'));
    await settleIo(tester);
    // A project is a workspace with its own tabs; it opens on agent.
    for (final t in ['agent', 'changes 2', 'files', 'preview']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Install Claude Code'), findsOneWidget); // no agent yet: one tap to get one
    await tester.tap(find.text('changes 2'));
    await settleIo(tester);

    expect(find.text('CHANGES · 2'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget); // no remote yet
    expect(find.text('README.md'), findsOneWidget);
    // No typing on a phone keyboard: Suggest writes the message.
    await tester.tap(find.text('Suggest'));
    await tester.pump();
    expect(find.text('Add notes.txt, update README.md'), findsOneWidget);
    await tester.tap(find.text('Commit all'));
    await settleIo(tester);
    expect(git.calls, contains('add -A -- README.md notes.txt'));
    expect(git.calls, contains('commit -q -m Add notes.txt, update README.md'));
    expect(find.text('Committed'), findsOneWidget); // in place, not a passing snackbar
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Committed'), findsNothing);

    // Files: the project's own folder, without leaving the project.
    await tester.tap(find.text('files'));
    await settleIo(tester);
    expect(find.text('main.dart'), findsOneWidget);
    expect(services.navigation.shownProject?.id, '1');

    // Back: a tab's own history, then the agent tab, then out to Projects.
    await tester.binding.handlePopRoute();
    await settleIo(tester);
    expect(services.navigation.workspaceTab, WorkspaceTab.agent);
    expect(find.text('Install Claude Code'), findsOneWidget);

    // A terminal opened here belongs to the project, not the Terminal tab.
    await tester.tap(find.text('Terminal'));
    await settleIo(tester);
    expect(services.navigation.tab.name, 'projects');
    expect(services.tabs.activeIn('/root/app')?.cwd, '/root/app');
    expect(find.text('app'), findsOneWidget); // its tab, in the workspace

    await tester.binding.handlePopRoute();
    await settleIo(tester);
    expect(services.navigation.atTabs, isTrue); // back on the project list
    await tester.tap(find.text('terminal'));
    await settleIo(tester);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('app'), findsNothing);

    // Coming back to the project finds its session where it was.
    await tester.tap(find.text('projects'));
    await settleIo(tester);
    await tester.tap(find.text('Weather app'));
    await settleIo(tester);
    expect(find.text('app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('a folder that is not a repo offers to start tracking it', (tester) async {
    File('${dir.path}/alpine/.aiterm-installed')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final services = (await tester.runAsync(AppServices.load))!;
    final git = _FakeGit()..repo = false;
    services.gitTools = GitTools(run: (script, onLine) async => 0);
    await services.gitTools.refresh();
    services.git = GitRegistry(git);
    await tester.pumpWidget(AiTermApp(services: services));
    await tester.pumpAndSettle();
    services.navigation.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const GitScreen(folder: '/root/plain')));
    await settleIo(tester);
    expect(find.text('Not tracked by git'), findsOneWidget);
    git.repo = true;
    await tester.tap(find.text('Start tracking'));
    await settleIo(tester);
    expect(git.calls, contains('init -q'));
    expect(find.text('CHANGES · 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('Files: Linux/Phone switcher, copy & paste, delete asks first', (tester) async {
    Directory('${dir.path}/alpine/root/proj').createSync(recursive: true);
    File('${dir.path}/alpine/root/notes.txt').writeAsStringSync('hi');
    File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    await boot(tester);
    await settleIo(tester);
    await tester.tap(find.text('files'));
    await settleIo(tester);

    // Phone without permission: a clear prompt, not an empty or broken list.
    await tester.tap(find.text('Phone'));
    await settleIo(tester);
    expect(find.text('Allow access'), findsOneWidget);
    await tester.tap(find.text('Linux'));
    await settleIo(tester);
    expect(find.text('notes.txt'), findsOneWidget);

    // Copy → paste bar → paste into proj.
    final notesRow = find.ancestor(of: find.text('notes.txt'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: notesRow, matching: find.byTooltip('Actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Paste here'), findsOneWidget);
    await tester.tap(find.text('proj'));
    await settleIo(tester);
    await tester.tap(find.text('Paste here'));
    await settleIo(tester);
    expect(File('${dir.path}/alpine/root/proj/notes.txt').existsSync(), isTrue);

    // Delete confirms before acting.
    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('can\'t be undone'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(File('${dir.path}/alpine/root/proj/notes.txt').existsSync(), isTrue);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });
}

/// git as the app sees it: a repo at /root/app with a modified and an
/// untracked file, no remote. Records every command.
class _FakeGit implements GitRunner {
  final calls = <String>[];
  bool repo = true;

  @override
  Future<GitResult> run(String folder, List<String> args, {String? stdin}) async {
    calls.add(args.join(' '));
    return switch (args.first) {
      'rev-parse' => repo ? GitResult(0, '$folder\n', '') : const GitResult(128, '', 'fatal: not a git repository'),
      'status' => const GitResult(
          0, '# branch.oid abc\x00# branch.head main\x001 .M N... 100644 100644 100644 aaa bbb README.md\x00? notes.txt\x00', ''),
      'log' => const GitResult(1, '', ''),
      _ => const GitResult(0, '', ''),
    };
  }
}
