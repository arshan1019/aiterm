import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../app_theme.dart';
import '../core/pty_channel.dart';
import '../core/shell_env.dart';
import '../widgets/extra_keys_bar.dart';

class TerminalScreen extends StatefulWidget {
  final AppColors colors;
  const TerminalScreen({super.key, required this.colors});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Terminal _terminal;
  final _session = PtySession();
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminal.onOutput = (data) => _session.write(data);
    _terminal.onResize = (w, h, _, _) => _session.resize(h, w);
    _boot();
  }

  Future<void> _boot() async {
    try {
      final argv = await ShellEnv.argv();
      final env = await ShellEnv.env();
      final cwd = await ShellEnv.cwd();
      await _session.start(argv: argv, env: env, cwd: cwd);
      _session.output.listen((bytes) {
        _terminal.write(utf8.decode(bytes, allowMalformed: true));
      });
      _session.onExit.listen((code) {
        _terminal.write('\r\n[process exited: $code]\r\n');
      });
      setState(() => _starting = false);
    } catch (e) {
      setState(() {
        _starting = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.colors;

    if (_starting) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not start shell:\n$_error',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.danger, fontFamily: 'monospace'),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Container(
            color: c.bg,
            padding: const EdgeInsets.all(4),
            child: TerminalView(
              _terminal,
              autofocus: true,
              backgroundOpacity: 0,
              theme: TerminalTheme(
                cursor: c.accent,
                selection: c.accent.withValues(alpha: 0.35),
                foreground: c.text,
                background: c.bg,
                black: c.bg,
                red: const Color(0xFFE2685A),
                green: const Color(0xFF6FBF73),
                yellow: const Color(0xFFD9B35C),
                blue: const Color(0xFF6C9EE5),
                magenta: const Color(0xFFB07CD1),
                cyan: const Color(0xFF5EC4A8),
                white: c.text,
                brightBlack: c.textMuted,
                brightRed: const Color(0xFFE2685A),
                brightGreen: const Color(0xFF6FBF73),
                brightYellow: const Color(0xFFD9B35C),
                brightBlue: const Color(0xFF6C9EE5),
                brightMagenta: const Color(0xFFB07CD1),
                brightCyan: const Color(0xFF5EC4A8),
                brightWhite: c.text,
                searchHitBackground: c.accent,
                searchHitBackgroundCurrent: c.accent,
                searchHitForeground: c.bg,
              ),
            ),
          ),
        ),
        ExtraKeysBar(colors: c, onKey: (data) => _session.write(data)),
      ],
    );
  }
}
