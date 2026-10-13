import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// User preferences, saved as JSON in the app's files directory. Loaded
/// before the first frame so the app never flashes the wrong theme.
class Settings extends ChangeNotifier {
  Settings._(this._file);

  static const minFontSize = 9.0, maxFontSize = 28.0;

  final File _file;
  bool _dark = true;
  double _fontSize = 14;
  bool _childLimitFixed = false;

  bool get dark => _dark;

  /// The Wireless debugging fix for the child-process limit succeeded.
  bool get childLimitFixed => _childLimitFixed;
  double get fontSize => _fontSize;

  static Future<Settings> load(String filesDir) async {
    final s = Settings._(File('$filesDir/settings.json'));
    try {
      final j = jsonDecode(await s._file.readAsString()) as Map<String, dynamic>;
      s._dark = j['dark'] as bool? ?? true;
      s._fontSize = ((j['fontSize'] as num?)?.toDouble() ?? 14).clamp(minFontSize, maxFontSize);
      s._childLimitFixed = j['childLimitFixed'] as bool? ?? false;
    } catch (_) {
      // First launch or unreadable: defaults.
    }
    return s;
  }

  set dark(bool v) {
    if (v == _dark) return;
    _dark = v;
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

  void _changed() {
    notifyListeners();
    _file.writeAsString(jsonEncode({'dark': _dark, 'fontSize': _fontSize, 'childLimitFixed': _childLimitFixed})).ignore();
  }
}
