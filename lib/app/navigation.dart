import 'package:flutter/widgets.dart';

/// [projects] is home: work happens in projects, where agents, terminals,
/// files and git all start in the project's folder.
enum AppTab { projects, terminal, files, settings }

/// Which top-level tab is showing, plus cross-tab requests ("show src in
/// Files"). Screens that keep their own back stack register a back handler.
class AppNavigation extends ChangeNotifier {
  AppTab _tab = AppTab.projects;
  AppTab get tab => _tab;

  /// The app's navigator: pages (a project, its changes) are pushed over
  /// the tabs, and switching tabs returns to them first.
  final navigatorKey = GlobalKey<NavigatorState>();

  void _toTabs() => navigatorKey.currentState?.popUntil((r) => r.isFirst);

  /// A folder the Files tab should open next; it clears this once handled.
  String? pendingFolder;

  /// Per-tab handlers for Android back; return true when they consumed it.
  final _backHandlers = <AppTab, bool Function()>{};

  void open(AppTab tab) {
    _toTabs();
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Builds a project's page (set by the app, which knows the screens).
  Route<void> Function(String projectId)? projectRoute;

  /// Shows project [id]'s page over the Projects tab, so back from it goes
  /// home: the way back from an agent's tab to the project it works on.
  void showProject(String id) {
    _toTabs();
    if (_tab != AppTab.projects) {
      _tab = AppTab.projects;
      notifyListeners();
    }
    if (projectRoute case final route?) navigatorKey.currentState?.push(route(id));
  }

  void showFolder(String path) {
    _toTabs();
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

  /// Android back: the current tab's own history first, then home
  /// (projects). False means nothing is left and the app should close.
  bool handleBack() {
    if (_backHandlers[_tab]?.call() ?? false) return true;
    if (_tab != AppTab.projects) {
      open(AppTab.projects);
      return true;
    }
    return false;
  }
}
