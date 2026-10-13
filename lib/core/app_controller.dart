import 'package:flutter/foundation.dart';

/// App-wide UI state the assistant can change ("dark mode", "bigger text",
/// "open settings", "show src in files").
class AppController extends ChangeNotifier {
  AppController._();
  static final instance = AppController._();

  static const tabTerminal = 0, tabFiles = 1, tabSettings = 2;

  bool isDark = true;
  double fontSize = 14;
  int tab = tabTerminal;

  /// A folder the Files tab should open; consumed by the Files tab.
  String? pendingFilesPath;

  /// Set by the Files tab: steps back in its history, false when at the start.
  bool Function()? filesBack;

  /// Android back button: Files history first, then back to the terminal.
  /// Returns false when the app should close.
  bool handleBack() {
    if (tab == tabFiles && (filesBack?.call() ?? false)) return true;
    if (tab != tabTerminal) {
      openTab(tabTerminal);
      return true;
    }
    return false;
  }

  void setDark(bool v) {
    isDark = v;
    notifyListeners();
  }

  void changeFontSize(int direction) {
    fontSize = (fontSize + 2 * direction).clamp(9, 28);
    notifyListeners();
  }

  void openTab(int t) {
    tab = t;
    notifyListeners();
  }

  void showInFiles(String path) {
    pendingFilesPath = path;
    tab = tabFiles;
    notifyListeners();
  }
}
