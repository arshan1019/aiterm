import 'package:flutter/services.dart';

/// The phone's colors (MainActivity: "aiterm/colors").
abstract final class SystemColors {
  static const _channel = MethodChannel('aiterm/colors');

  /// The wallpaper's accent on Android 12+; null before that, in tests,
  /// or when the phone won't say.
  static Future<Color?> accent() async {
    try {
      final argb = await _channel.invokeMethod<int>('accent');
      return argb == null ? null : Color(argb);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
