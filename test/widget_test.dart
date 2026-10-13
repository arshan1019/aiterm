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

  Future<AppServices> boot(WidgetTester tester) async {
    final services = (await tester.runAsync(AppServices.load))!;
    await tester.pumpWidget(AiTermApp(services: services));
    await tester.pumpAndSettle();
    return services;
  }

  // Lets real file IO (listing folders, starting sessions) finish.
  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows the tabs and Linux setup', (tester) async {
    await boot(tester);
    expect(find.text('terminal'), findsOneWidget);
    expect(find.text('files'), findsOneWidget);
    expect(find.text('settings'), findsOneWidget);
    expect(find.text('Install Alpine'), findsOneWidget);
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
    final r = tester.state<TerminalViewState>(find.byType(TerminalView).first).renderTerminal;
    debugPrint('DIAG row6="${session.terminal.buffer.lines[6].getText()}" lines=${session.terminal.buffer.lines.length} '
        'size=${session.terminal.viewWidth}x${session.terminal.viewHeight} tap=$url cellAtTap=${r.getCellOffset(r.globalToLocal(url))}');
    await tester.tapAt(url);
    await tester.pump();
    debugPrint('DIAG selection=${session.selection.selection}');
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
  });
}
