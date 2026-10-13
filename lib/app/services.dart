import 'package:flutter/widgets.dart';
import '../assistant/assistant.dart';
import '../assistant/needle.dart';
import '../assistant/tool_call.dart';
import '../linux/linux_environment.dart';
import '../platform/android_env.dart';
import '../settings/settings.dart';
import '../terminal/terminal_tabs.dart';
import 'navigation.dart';

/// Everything the app's screens share, created once at startup and handed
/// down through [AppScope]. Plain objects with explicit dependencies; no
/// hidden singletons.
class AppServices {
  AppServices._(this.paths, this.settings, this.linux, this.tabs)
      : navigation = AppNavigation(),
        assistant = Assistant(Needle(paths)) {
    // Android may kill a backgrounded app without warning: save tabs as
    // soon as the app leaves the screen.
    _lifecycle = AppLifecycleListener(onHide: () => tabs.save().ignore());
  }

  // ignore: unused_field
  late final AppLifecycleListener _lifecycle;

  final AppPaths paths;
  final Settings settings;
  final AppNavigation navigation;
  final LinuxEnvironment linux;
  final TerminalTabs tabs;
  final Assistant assistant;

  /// Loads everything the first frame depends on.
  static Future<AppServices> load() async {
    final paths = await AndroidEnv.paths();
    final linux = LinuxEnvironment(paths);
    final tabs = TerminalTabs(paths.filesDir);
    final (settings, _, _) = await (Settings.load(paths.filesDir), linux.load(), tabs.load()).wait;
    return AppServices._(paths, settings, linux, tabs);
  }

  /// Runs an app action the assistant picked ("dark mode", "bigger text",
  /// "show src in files", "restart the shell").
  void perform(ToolCall action) {
    switch (action.tool) {
      case 'set_font_size':
        settings.stepFontSize(action.args['change'] == 'smaller' ? -1 : 1);
      case 'set_theme':
        settings.dark = action.args['theme'] != 'light';
      case 'open_tab':
        navigation.open(switch (action.args['tab']) {
          'files' => AppTab.files,
          'settings' => AppTab.settings,
          _ => AppTab.terminal,
        });
      case 'show_in_files':
        navigation.showFolder(action.args['path'] ?? '~');
      case 'restart_shell':
        tabs.active.restart(linux.sessionSpec, alpine: !linux.usesAndroidShell);
    }
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

extension ServicesContext on BuildContext {
  AppServices get services => AppScope.of(this);
}
