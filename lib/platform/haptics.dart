import 'package:flutter/services.dart';

/// Touch feedback with Android's own constants (MainActivity: "aiterm/haptics"),
/// so it follows the system's vibration settings, and the app's own switch
/// ([enabled], Settings → Haptic feedback).
///
/// When (Android's haptics principles, One UI): less is more; clear clicks,
/// never buzzy; strength follows importance; fired on the frame the change
/// shows (feedback within ~30–50 ms reads as instant); never for what the
/// user isn't looking at, for typing, or for repeated actions like scrolls.
///
///  - tick: a choice made, a message sent, a block opened
///  - toggle: a switch flipped
///  - confirm: something finished well (an agent's turn, a commit, allowed)
///  - reject: something failed or was refused (two quick pulses on One UI)
///  - attention: the agent needs an answer (a permission request)
///  - longPress: a long press opened a menu
abstract final class Haptics {
  static const _channel = MethodChannel('aiterm/haptics');

  /// Off in Settings: no vibration at all.
  static bool enabled = true;

  static Future<void> _play(String kind) async {
    if (!enabled) return;
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

  /// Something needs the user's answer (a firmer single click).
  static Future<void> attention() => _play('longPress');
}
