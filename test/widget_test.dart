import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiterm/main.dart';

void main() {
  testWidgets('first launch shows the bottom navigation and Linux setup', (tester) async {
    final dir = Directory.systemTemp.createTempSync('aiterm_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('aiterm/env'),
      (call) async => {
        'nativeLibDir': '${dir.path}/lib',
        'filesDir': dir.path,
        'cacheDir': dir.path,
      },
    );

    await tester.pumpWidget(const AiTermApp());
    // DistroManager.init touches the real filesystem; let that finish.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text('aiterm'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Install Alpine'), findsOneWidget);
  });
}
