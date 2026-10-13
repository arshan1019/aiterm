import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/app/navigation.dart';
import 'package:aiterm/terminal/session_presence.dart';

void main() {
  test('only the active tab of a visible Terminal screen counts as seen', () {
    expect(visibleSession(appVisible: true, tab: AppTab.terminal, activePtyId: 5), 5);
    expect(visibleSession(appVisible: true, tab: AppTab.files, activePtyId: 5), isNull);
    expect(visibleSession(appVisible: false, tab: AppTab.terminal, activePtyId: 5), isNull);
    expect(visibleSession(appVisible: true, tab: AppTab.terminal, activePtyId: null), isNull);
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
