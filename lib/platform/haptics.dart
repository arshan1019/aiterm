import 'package:flutter/services.dart';

/// Touch feedback with Android's own constants (MainActivity: "aiterm/haptics"),
/// so it follows the system's vibration settings. Used sparingly, for
/// moments that matter (Android: less is more): a toggle, a result, an
/// error, a long press. Never for typing or repeated actions.
abstract final class Haptics {
  static const _channel = MethodChannel('aiterm/haptics');

  static Future<void> _play(String kind) async {
    try {
      await _channel.invokeMethod(kind);
    } on MissingPluginException {
      // Tests and platforms without the channel.
    } on PlatformException {
      // A device without the constant: no feedback.
    }
  }

  /// Something finished well (committed, pushed, set up).
  static Future<void> confirm() => _play('confirm');

  /// Something failed.
  static Future<void> reject() => _play('reject');

  static Future<void> toggle(bool on) => _play(on ? 'toggleOn' : 'toggleOff');

  /// A small step (a threshold crossed, a choice changed).
  static Future<void> tick() => _play('tick');

  /// A long press that opened a menu.
  static Future<void> longPress() => _play('longPress');
}
