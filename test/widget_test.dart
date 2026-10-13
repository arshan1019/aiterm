import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/app.dart';
import 'package:aiterm/app/services.dart';
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
    expect(find.text('Install Alpine'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('walks through every screen without framework errors', (tester) async {
    await boot(tester);

    await tester.tap(find.text('Use Android shell instead'));
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
    await tester.tap(find.text('✦'));
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

  testWidgets('Files: open a terminal here from the menu and from empty space', (tester) async {
    Directory('${dir.path}/alpine/root/proj').createSync(recursive: true);
    File('${dir.path}/alpine/.aiterm-installed').writeAsStringSync('x');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    final services = await boot(tester);
    await settleIo(tester);

    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();
    expect(services.navigation.tab.name, 'terminal');
    expect(services.tabs.active.cwd, '/root');
    expect(find.text('root'), findsOneWidget); // the new tab, named after the folder

    // Hold empty space below the entries.
    await tester.tap(find.text('files'));
    await settleIo(tester);
    await tester.tap(find.text('proj'));
    await settleIo(tester);
    await tester.longPressAt(tester.getCenter(find.text('Empty folder')) + const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();
    expect(services.tabs.active.cwd, '/root/proj');
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('switching tabs or screens does not pop the keyboard up', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Use Android shell instead'));
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

  testWidgets('home is AI agents; first launch sets up Linux there', (tester) async {
    await boot(tester, home: true);
    expect(find.text('agents'), findsOneWidget);
    expect(find.text('Install Alpine'), findsOneWidget); // first launch sets up Linux here
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });

  testWidgets('with Linux set up, home lists the agents to install', (tester) async {
    File('${dir.path}/alpine/.aiterm-installed')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final services = await boot(tester, home: true);
    expect(services.navigation.tab.name, 'agents');
    for (final name in ['Claude Code', 'Gemini CLI', 'Codex CLI']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Install'), findsNWidgets(3));
    expect(find.textContaining('Sign in the first time'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the debounced tab save
  });
}
