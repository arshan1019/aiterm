import 'package:flutter/foundation.dart';

enum AppTab { terminal, files, settings }

/// Which top-level tab is showing, plus cross-tab requests ("show src in
/// Files"). Screens that keep their own back stack register a back handler.
class AppNavigation extends ChangeNotifier {
  AppTab _tab = AppTab.terminal;
  AppTab get tab => _tab;

  /// A folder the Files tab should open next; it clears this once handled.
  String? pendingFolder;

  /// Per-tab handlers for Android back; return true when they consumed it.
  final _backHandlers = <AppTab, bool Function()>{};

  void open(AppTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  void showFolder(String path) {
    pendingFolder = path;
    _tab = AppTab.files;
    notifyListeners();
  }

  void setBackHandler(AppTab tab, bool Function()? handler) {
    if (handler == null) {
      _backHandlers.remove(tab);
    } else {
      _backHandlers[tab] = handler;
    }
  }

  /// Android back: the current tab's own history first, then back to the
  /// terminal. False means nothing is left and the app should close.
  bool handleBack() {
    if (_backHandlers[_tab]?.call() ?? false) return true;
    if (_tab != AppTab.terminal) {
      open(AppTab.terminal);
      return true;
    }
    return false;
  }
}
