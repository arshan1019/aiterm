import 'package:flutter_test/flutter_test.dart';

import 'package:aiterm/main.dart';

void main() {
  testWidgets('App boots and shows the bottom navigation', (tester) async {
    await tester.pumpWidget(const AiTermApp());
    await tester.pump();

    expect(find.text('aiterm'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
