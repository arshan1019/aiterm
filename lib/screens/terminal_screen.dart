import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../app_theme.dart';
import '../core/distro_manager.dart';
import '../core/pty_channel.dart';
import '../core/shell_env.dart';
import '../widgets/extra_keys_bar.dart';

enum _Phase { loading, setup, running, exited }

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

  final _distro = DistroManager.instance;
  final _terminal = Terminal(maxLines: 10000);
  final _utf8 = const Utf8Decoder(allowMalformed: true);
  PtySession? _session;
  _Phase _phase = _Phase.loading;
  bool _useAndroidShell = false;
  String? _status;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) => _session?.write(data);
    _terminal.onResize = (w, h, _, _) => _session?.resize(h, w);
    _boot();
  }

  Future<void> _boot() async {
    try {
      await _distro.init();
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (_distro.installed) {
      await _start();
    } else {
      setState(() => _phase = _Phase.setup);
    }
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _status = 'Starting';
      _progress = null;
    });
    try {
      await _distro.install((status, progress) {
        if (mounted) {
          setState(() {
            _status = status;
            _progress = progress;
          });
        }
      });
      await _start();
    } catch (e) {
      setState(() {
        _status = null;
        _error = '$e';
      });
    }
  }

  Future<void> _start() async {
    await _session?.dispose();
    final session = PtySession();
    _session = session;
    try {
      final spec = _useAndroidShell
          ? await ShellEnv.androidShell()
          : await _distro.sessionSpec();
      await session.start(
        argv: spec.argv,
        env: spec.env,
        cwd: spec.cwd,
        rows: _terminal.viewHeight,
        cols: _terminal.viewWidth,
      );
      session.output.listen((bytes) => _terminal.write(_utf8.convert(bytes)));
      session.onExit.listen((code) {
        _terminal.write('\r\n[process exited: $code]\r\n');
        if (mounted) setState(() => _phase = _Phase.exited);
      });
      setState(() => _phase = _Phase.running);
    } catch (e) {
      setState(() {
        _phase = _distro.installed || _useAndroidShell ? _Phase.exited : _Phase.setup;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = widget.colors;
    switch (_phase) {
      case _Phase.loading:
        return Center(child: CircularProgressIndicator(color: c.accent));
      case _Phase.setup:
        return _SetupView(
          colors: c,
          status: _status,
          progress: _progress,
          error: _error,
          onInstall: _status == null ? _install : null,
          onSkip: _status == null
              ? () {
                  _useAndroidShell = true;
                  _start();
                }
              : null,
        );
      case _Phase.running:
      case _Phase.exited:
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
                  theme: _theme(c),
                ),
              ),
            ),
            if (_phase == _Phase.exited)
              Material(
                color: c.surface,
                child: ListTile(
                  dense: true,
                  title: Text(
                    _error ?? 'Session ended',
                    style: TextStyle(color: _error == null ? c.textMuted : c.danger),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      _error = null;
                      _start();
                    },
                    child: Text('Restart', style: TextStyle(color: c.accent)),
                  ),
                ),
              ),
            ExtraKeysBar(colors: c, onKey: (data) => _session?.write(data)),
          ],
        );
    }
  }

  TerminalTheme _theme(AppColors c) => TerminalTheme(
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
      );
}

class _SetupView extends StatelessWidget {
  final AppColors colors;
  final String? status;
  final double? progress;
  final String? error;
  final VoidCallback? onInstall;
  final VoidCallback? onSkip;

  const _SetupView({
    required this.colors,
    required this.status,
    required this.progress,
    required this.error,
    required this.onInstall,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set up Linux',
                  style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Downloads Alpine Linux (~4 MB) and runs it with proot. '
                'You get apk, so you can install node, git, python, and tools '
                'like Claude Code.',
                style: TextStyle(color: c.textMuted, height: 1.4),
              ),
              const SizedBox(height: 20),
              if (status != null) ...[
                Text(status!, style: TextStyle(color: c.text, fontSize: 13)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  color: c.accent,
                  backgroundColor: c.surfaceAlt,
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.bg,
                    ),
                    onPressed: onInstall,
                    child: const Text('Install Alpine'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: onSkip,
                    child: Text('Use Android shell instead',
                        style: TextStyle(color: c.textMuted)),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: TextStyle(color: c.danger, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
