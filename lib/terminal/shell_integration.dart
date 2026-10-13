/// Shell integration: escape sequences the shell prints so the app knows
/// what's happening inside it, the same conventions VS Code, iTerm2 and
/// WezTerm use. lib/linux/shell_profile.dart makes the shell emit them.
///
///   OSC 7;file://host/path     current directory
///   OSC 133;A / C / D;status   prompt shown / command started / finished
///   OSC 9;text                 notification (iTerm2; Claude Code uses it)
///   OSC 777;notify;title;body  notification (rxvt / Ghostty / foot)
library;

sealed class ShellEvent {
  const ShellEvent();
}

class CwdChanged extends ShellEvent {
  const CwdChanged(this.path);
  final String path;
  @override
  bool operator ==(Object other) => other is CwdChanged && other.path == path;
  @override
  int get hashCode => path.hashCode;
  @override
  String toString() => 'CwdChanged($path)';
}

class PromptShown extends ShellEvent {
  const PromptShown();
  @override
  bool operator ==(Object other) => other is PromptShown;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'PromptShown';
}

class CommandStarted extends ShellEvent {
  const CommandStarted();
  @override
  bool operator ==(Object other) => other is CommandStarted;
  @override
  int get hashCode => 2;
  @override
  String toString() => 'CommandStarted';
}

class CommandFinished extends ShellEvent {
  const CommandFinished(this.exitCode);
  final int? exitCode;
  @override
  bool operator ==(Object other) => other is CommandFinished && other.exitCode == exitCode;
  @override
  int get hashCode => Object.hash(3, exitCode);
  @override
  String toString() => 'CommandFinished($exitCode)';
}

class ShellNotification extends ShellEvent {
  const ShellNotification(this.title, this.body);
  final String? title;
  final String body;
  @override
  bool operator ==(Object other) => other is ShellNotification && other.title == title && other.body == body;
  @override
  int get hashCode => Object.hash(title, body);
  @override
  String toString() => 'ShellNotification($title, $body)';
}

/// Interprets an OSC sequence xterm didn't handle itself. [args] are the
/// parts after the code, split on ';' (rejoined where text may contain ';').
ShellEvent? parseOsc(String code, List<String> args) {
  switch (code) {
    case '7':
      final uri = Uri.tryParse(args.join(';'));
      if (uri == null || uri.scheme != 'file') return null;
      return CwdChanged(Uri.decodeComponent(uri.path));
    case '133':
      return switch (args.firstOrNull) {
        'A' => const PromptShown(),
        'C' => const CommandStarted(),
        'D' => CommandFinished(args.length > 1 ? int.tryParse(args[1]) : null),
        _ => null,
      };
    case '9':
      // OSC 9;4;… is ConEmu's progress report, not a message.
      if (args.firstOrNull == '4' && args.length > 1) return null;
      final body = args.join(';');
      return body.isEmpty ? null : ShellNotification(null, body);
    case '777':
      if (args.firstOrNull != 'notify' || args.length < 2) return null;
      final title = args[1];
      final body = args.length > 2 ? args.sublist(2).join(';') : '';
      return ShellNotification(title.isEmpty ? null : title, body);
  }
  return null;
}

/// Every OSC event in raw terminal [text] (used by tests and tooling).
List<ShellEvent> oscEventsIn(String text) {
  final events = <ShellEvent>[];
  for (final m in RegExp(r'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)').allMatches(text)) {
    final parts = m.group(1)!.split(';');
    final e = parseOsc(parts.first, parts.sublist(1));
    if (e != null) events.add(e);
  }
  return events;
}

class CommandDone {
  const CommandDone({required this.exitCode, required this.duration});
  final int? exitCode;
  final Duration duration;
}

/// Turns Enter presses and prompt marks into finished commands: a command
/// runs from the Enter that left a prompt until the next prompt appears.
class CommandTracker {
  CommandTracker({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _startedAt;
  int? _lastExit;

  /// A command is running (Enter was pressed and no prompt has come back).
  bool get busy => _startedAt != null;

  void onEnter() => _startedAt ??= _clock();

  /// Returns the finished command when [e] closes one.
  CommandDone? onEvent(ShellEvent e) {
    switch (e) {
      case CommandFinished(:final exitCode):
        _lastExit = exitCode;
      case PromptShown():
        final started = _startedAt;
        final exit = _lastExit;
        _startedAt = null;
        _lastExit = null;
        if (started != null) return CommandDone(exitCode: exit, duration: _clock().difference(started));
      default:
    }
    return null;
  }
}
