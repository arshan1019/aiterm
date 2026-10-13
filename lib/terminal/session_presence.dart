import '../app/navigation.dart';

/// The session the user is looking at: the active tab, while the Terminal
/// screen shows and the app is on screen. Native notifications skip it.
int? visibleSession({required bool appVisible, required AppTab tab, required int? activePtyId}) =>
    appVisible && tab == AppTab.terminal ? activePtyId : null;

/// Tells the native side (which decides notifications even when this UI is
/// gone) what's on screen and what each session's tab is called. Sends
/// only changes.
class SessionPresence {
  SessionPresence({required this.setVisible, required this.setTitle});

  final void Function(int? id) setVisible;
  final void Function(int id, String title) setTitle;

  bool _first = true;
  int? _visible;
  final _titles = <int, String>{};

  void update({required int? visibleId, required Map<int, String> titles}) {
    if (_first || visibleId != _visible) {
      _first = false;
      _visible = visibleId;
      setVisible(visibleId);
    }
    for (final MapEntry(key: id, value: title) in titles.entries) {
      if (_titles[id] != title) {
        _titles[id] = title;
        setTitle(id, title);
      }
    }
  }
}
