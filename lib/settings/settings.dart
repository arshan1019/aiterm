import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../shared/fs_atomic.dart';

/// Light, dark, or whatever the phone uses.
enum ThemeChoice { system, light, dark }

/// User preferences, saved as JSON in the app's files directory. Loaded
/// before the first frame so the app never flashes the wrong theme.
class Settings extends ChangeNotifier {
  Settings._(this._file);

  static const minFontSize = 9.0, maxFontSize = 28.0;

  final File _file;
  ThemeChoice _theme = ThemeChoice.system;
  bool _wallpaperColors = false;
  bool _blackTerminal = false;
  bool _darkTerminal = false;
  bool _compact = false;
  double _fontSize = 14;
  bool _childLimitFixed = false;

  ThemeChoice get theme => _theme;

  /// The accent follows the wallpaper (Android 12+).
  bool get wallpaperColors => _wallpaperColors;

  /// A pure black terminal when it's dark (OLED screens).
  bool get blackTerminal => _blackTerminal;

  /// The terminal stays dark in the light theme.
  bool get darkTerminal => _darkTerminal;

  /// Shorter list rows (48dp instead of 56dp).
  bool get compact => _compact;

  /// The Wireless debugging fix for the child-process limit succeeded.
  bool get childLimitFixed => _childLimitFixed;
  double get fontSize => _fontSize;

  static Future<Settings> load(String filesDir) async {
    final s = Settings._(File('$filesDir/settings.json'));
    try {
      final j = jsonDecode(await s._file.readAsString()) as Map<String, dynamic>;
      s._theme =
          ThemeChoice.values.asNameMap()[j['theme']] ??
          // Before the theme choice there was a dark switch.
          switch (j['dark']) {
            true => ThemeChoice.dark,
            false => ThemeChoice.light,
            _ => ThemeChoice.system,
          };
      s._wallpaperColors = j['wallpaperColors'] as bool? ?? false;
      s._blackTerminal = j['blackTerminal'] as bool? ?? false;
      s._darkTerminal = j['darkTerminal'] as bool? ?? false;
      s._compact = j['compact'] as bool? ?? false;
      s._fontSize = ((j['fontSize'] as num?)?.toDouble() ?? 14).clamp(minFontSize, maxFontSize);
      s._childLimitFixed = j['childLimitFixed'] as bool? ?? false;
    } catch (_) {
      // First launch or unreadable: defaults.
    }
    return s;
  }

  set theme(ThemeChoice v) {
    if (v == _theme) return;
    _theme = v;
    _changed();
  }

  set wallpaperColors(bool v) {
    if (v == _wallpaperColors) return;
    _wallpaperColors = v;
    _changed();
  }

  set blackTerminal(bool v) {
    if (v == _blackTerminal) return;
    _blackTerminal = v;
    _changed();
  }

  set darkTerminal(bool v) {
    if (v == _darkTerminal) return;
    _darkTerminal = v;
    _changed();
  }

  set compact(bool v) {
    if (v == _compact) return;
    _compact = v;
    _changed();
  }

  void markChildLimitFixed() {
    _childLimitFixed = true;
    _changed();
  }

  /// Steps the terminal font size up (+1) or down (-1).
  void stepFontSize(int direction) {
    final v = (_fontSize + 2 * direction).clamp(minFontSize, maxFontSize);
    if (v == _fontSize) return;
    _fontSize = v;
    _changed();
  }

  Future<void> _saving = Future.value();

  /// Done when every change so far is on disk.
  @visibleForTesting
  Future<void> get saved => _saving;

  void _changed() {
    notifyListeners();
    // One write at a time, each atomic: quick changes in a row (switches
    // flipped fast) used to overlap and could leave a broken file.
    final json = jsonEncode({
      'theme': _theme.name,
      'wallpaperColors': _wallpaperColors,
      'blackTerminal': _blackTerminal,
      'darkTerminal': _darkTerminal,
      'compact': _compact,
      'fontSize': _fontSize,
      'childLimitFixed': _childLimitFixed,
    });
    _saving = _saving.then((_) => writeFileAtomic(_file.path, json)).catchError((Object _) {});
  }
}
