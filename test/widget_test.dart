import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/app.dart';
import 'package:aiterm/app/services.dart';

// Widget tests overflow the stack inside the Acode sandbox this project is
// developed in; they run on CI and desktop.
void main() {
  testWidgets('first launch shows the tabs and Linux setup', (tester) async {
    final dir = Directory.systemTemp.createTempSync('aiterm_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('aiterm/env'),
      (call) async => {'nativeLibDir': '${dir.path}/lib', 'filesDir': dir.path, 'cacheDir': dir.path, 'uptimeMs': '1000'},
    );

    final services = (await tester.runAsync(AppServices.load))!;
    await tester.pumpWidget(AiTermApp(services: services));
    await tester.pump();

    expect(find.text('terminal'), findsOneWidget);
    expect(find.text('files'), findsOneWidget);
    expect(find.text('settings'), findsOneWidget);
    expect(find.text('Install Alpine'), findsOneWidget);
  });
}
