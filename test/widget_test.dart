import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/app.dart';
import 'package:aiterm/app/services.dart';

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

  Future<void> boot(WidgetTester tester) async {
    final services = (await tester.runAsync(AppServices.load))!;
    await tester.pumpWidget(AiTermApp(services: services));
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
}
