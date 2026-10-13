import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// [projects] is home: work happens in projects, where agents, terminals,
/// files and git all start in the project's folder.
enum AppTab { projects, terminal, files, settings }

/// A project's workspace has its own tabs; [agent] is where it opens.
enum WorkspaceTab { agent, changes, files, preview }

/// Which project a workspace page shows (its route's arguments).
class ProjectRef {
  const ProjectRef(this.id, this.path);
  final String id;

  /// The project folder (guest path).
  final String path;
}

/// What's on screen and how to move around. The rules (docs/USERFLOW.md,
/// "Navigation"):
///
/// - Tabs aren't history: switching tabs, in the app or in a project,
///   never adds a back step.
/// - Back: close what's on top (sheet, page), then the tab's own history
///   (folders, web pages), then the first tab of that level, then leave
///   the level (a project returns to Projects; the app closes).
/// - A project opens over Projects, wherever it was opened from, so back
///   from a project always lands on the project list.
/// - Things a project has (its sessions, changes, files, preview) open in
///   its workspace, never by leaving it.
class AppNavigation extends ChangeNotifier {
  AppTab _tab = AppTab.projects;
  AppTab get tab => _tab;

  /// The app's navigator: pages (a project, its changes) are pushed over
  /// the tabs, and switching tabs returns to them first.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Tracks the page stack (give it to the app's navigator).
  late final NavigatorObserver observer = _RouteTracker(this);
  final _routes = <Route<dynamic>>[];

  static const projectRouteName = 'project';

  /// Builds a project's workspace page (set by the app, which knows the
  /// screens).
  Route<void> Function(ProjectRef project)? projectRoute;

  /// No page is open over the tabs.
  bool get atTabs => _routes.length <= 1;

  /// The project whose workspace is the top page, if any.
  ProjectRef? get shownProject => _refOf(_routes.lastOrNull);

  /// The project whose workspace is open, even under another page.
  ProjectRef? get openProject => _routes.map(_refOf).whereType<ProjectRef>().firstOrNull;

  static ProjectRef? _refOf(Route<dynamic>? r) =>
      r?.settings.name == projectRouteName ? r!.settings.arguments as ProjectRef? : null;

  WorkspaceTab _workspaceTab = WorkspaceTab.agent;

  /// The tab showing in the open workspace (only one is open at a time).
  WorkspaceTab get workspaceTab => _workspaceTab;

  /// A folder the Files tab should open next; it clears this once handled.
  String? pendingFolder;

  /// A folder the open workspace's Files tab should open next.
  String? pendingProjectFolder;

  /// Per-tab handlers for Android back; return true when they consumed it.
  final _backHandlers = <AppTab, bool Function()>{};

  /// The workspace tabs' own back history (folders, web pages).
  final workspaceBack = <WorkspaceTab, Future<bool> Function()>{};

  void _toTabs() => navigatorKey.currentState?.popUntil((r) => r.isFirst);

  void open(AppTab tab) {
    _toTabs();
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Opens [project]'s workspace (at [tab] if given): over Projects, so
  /// back from it goes home. Already open: pages over it close and only
  /// the tab changes.
  void showProject(ProjectRef project, {WorkspaceTab? tab}) {
    final nav = navigatorKey.currentState;
    if (openProject?.id == project.id) {
      nav?.popUntil((r) => _refOf(r)?.id == project.id);
      openWorkspaceTab(tab ?? _workspaceTab);
      return;
    }
    _toTabs();
    _tab = AppTab.projects;
    _workspaceTab = tab ?? WorkspaceTab.agent;
    notifyListeners();
    if (projectRoute case final route?) nav?.push(route(project));
  }

  void openWorkspaceTab(WorkspaceTab tab) {
    if (tab == _workspaceTab) return;
    _workspaceTab = tab;
    notifyListeners();
  }

  /// Shows [path] (a guest path) in Files: the open project's own Files tab
  /// when it's inside that project, else the Files tab.
  void showFolder(String path) {
    if (openProject case final p? when path == p.path || path.startsWith('${p.path}/')) {
      pendingProjectFolder = path;
      showProject(p, tab: WorkspaceTab.files);
      notifyListeners();
      return;
    }
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

  /// Android back over the tabs: the current tab's own history first, then
  /// home (projects). False means nothing is left and the app should close.
  bool handleBack() {
    if (_backHandlers[_tab]?.call() ?? false) return true;
    if (_tab != AppTab.projects) {
      open(AppTab.projects);
      return true;
    }
    return false;
  }

  /// Android back in a workspace: the tab's own history, then its first
  /// tab. False means leave the workspace.
  Future<bool> handleWorkspaceBack() async {
    if (await workspaceBack[_workspaceTab]?.call() ?? false) return true;
    if (_workspaceTab != WorkspaceTab.agent) {
      openWorkspaceTab(WorkspaceTab.agent);
      return true;
    }
    return false;
  }

  void _routesChanged() {
    // Route changes can land mid-frame; listeners rebuild after it.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

/// Tracks pages only: a sheet or dialog over a page doesn't change which
/// page is showing.
class _RouteTracker extends NavigatorObserver {
  _RouteTracker(this._nav);
  final AppNavigation _nav;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _nav._routes.add(route);
    _nav._routesChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_nav._routes.remove(route)) _nav._routesChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_nav._routes.remove(route)) _nav._routesChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _nav._routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _nav._routes[i] = newRoute;
    } else if (newRoute is PageRoute) {
      _nav._routes.add(newRoute);
    }
    _nav._routesChanged();
  }
}
