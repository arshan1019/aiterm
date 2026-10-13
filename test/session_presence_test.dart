import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/terminal/session_presence.dart';

void main() {
  test('the terminal on screen counts as seen while the app is visible', () {
    expect(visibleSession(appVisible: true, shownPtyId: 5), 5);
    expect(visibleSession(appVisible: false, shownPtyId: 5), isNull);
    expect(visibleSession(appVisible: true, shownPtyId: null), isNull);
  });

  test('reports changes once, and titles per session', () {
    final visible = <int?>[];
    final titles = <(int, String)>[];
    final p = SessionPresence(setVisible: visible.add, setTitle: (id, t) => titles.add((id, t)));

    p.update(visibleId: 3, titles: {3: 'shell', 4: 'build'});
    p.update(visibleId: 3, titles: {3: 'shell', 4: 'build'}); // no change
    p.update(visibleId: null, titles: {3: 'shell', 4: 'claude'});

    expect(visible, [3, null]);
    expect(titles, [(3, 'shell'), (4, 'build'), (4, 'claude')]);
  });
}
